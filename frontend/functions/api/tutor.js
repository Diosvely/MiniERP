// =====================================================================
// TUTOR DE ASIENTOS · Cloudflare Pages Function  →  POST /api/tutor
// ---------------------------------------------------------------------
// El usuario describe una operación y la IA propone el asiento. La IA PROPONE, el ERP COMPRUEBA, el usuario DECIDE.
// 1. Pide a Supabase erp.entry_tutor_context CON LA SESIÓN DEL USUARIO (solo el owner; PGC, impuestos vigentes, NRV).
// 2. El modelo de Workers AI propone el asiento en JSON (cuentas del PGC, impuestos por su código, NRV de la lista).
// 3. erp.validate_proposed_entry lo comprueba: subcuentas reales, cuota del impuesto, Debe = Haber, criterio…
// 4. Si hay errores, se le devuelven al modelo UNA vez para que lo corrija (la "segunda vuelta").
// Nada se contabiliza: la web carga el resultado como borrador en el formulario de asientos.
// Usa el mismo binding "AI" y las mismas variables que /api/ai.
// =====================================================================

const DEFAULT_MODEL = '@cf/mistralai/mistral-small-3.1-24b-instruct'
const MAX_TEXT = 1000

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json; charset=utf-8' } })

const INSTRUCTIONS = {
  es: `Eres profesor de contabilidad española (PGC 2007, modificado por el RD 1/2021). Un alumno describe una operación
y tú propones el asiento. Recibes en JSON el plan de cuentas (chart_of_accounts), los tipos de IVA / IGIC VIGENTES de
la empresa (tax_codes), las retenciones (withholdings) y las normas de registro y valoración (valuation_rules).

Reglas:
- Usa SOLO cuentas de chart_of_accounts, con su número de 3 o 4 dígitos (por ejemplo "217", "4751", "523").
- Impuestos: una línea con "role": "tax", el "tax_code" de tax_codes que corresponda y su "tax_base". La cuota la calcula el ERP:
  pon tu cálculo en "amount", pero el código es lo importante. Si la empresa es de Canarias es IGIC, no IVA.
  Si tax_setup es false, usa la cuenta 472 / 477 sin tax_code.
- Retenciones (IRPF): "role": "withholding" con la cuenta de withholdings.
- El tercero (cliente, proveedor, acreedor): "role": "partner". El inmovilizado se compra a la 523 (o 173 a largo plazo), no a la 400.
  Bancos y caja: "role": "cash". El resto: "role": "base" u "other".
- Importes positivos en euros, con punto decimal. "side": "debit" (Debe) o "credit" (Haber). Debe = Haber.
- "valuation_rule": el código de valuation_rules que se aplica (por ejemplo "NRV2"). No cites artículos ni normas que no estén en la lista.
- Si falta un dato (el tipo de IVA, la forma de pago…), elige lo más habitual y dilo en "assumptions".
- Escribe para alguien que está aprendiendo: breve y claro.

Responde SOLO con un objeto JSON válido, sin texto antes ni después:
{"explanation": "2 o 3 frases: qué operación es y cómo se registra",
 "valuation_rule": "NRV…",
 "partner_name": "nombre del tercero si el alumno lo menciona, o vacío",
 "assumptions": ["supuestos que has hecho"],
 "lines": [{"account": "217", "side": "debit", "amount": 1200, "role": "base", "description": "por qué esta cuenta, en pocas palabras"},
           {"account": "472", "side": "debit", "amount": 252, "role": "tax", "tax_code": "VAT21", "tax_base": 1200, "description": "…"}],
 "question": "una pregunta corta para que el alumno compruebe que lo ha entendido"}`,
  en: `You are a teacher of Spanish accounting (Spanish GAAP – PGC 2007, amended by RD 1/2021). A student describes a
transaction and you propose the journal entry. You receive in JSON the chart of accounts (chart_of_accounts), the
company's CURRENT VAT / IGIC rates (tax_codes), withholdings and the valuation rules (valuation_rules).

Rules:
- Use ONLY accounts from chart_of_accounts, with their 3 or 4 digit number (for example "217", "4751", "523").
- Taxes: one line with "role": "tax", the matching "tax_code" from tax_codes and its "tax_base". The ERP calculates the amount:
  put your calculation in "amount", but the code is what matters. If the company is in the Canary Islands it is IGIC, not VAT.
  If tax_setup is false, use account 472 / 477 without tax_code.
- Withholdings (IRPF): "role": "withholding" with the account from withholdings.
- The third party (customer, supplier, creditor): "role": "partner". Fixed assets are bought against 523 (or 173 long term), not 400.
  Banks and cash: "role": "cash". Anything else: "role": "base" or "other".
- Positive amounts in euros, with a decimal point. "side": "debit" or "credit". Debits = credits.
- "valuation_rule": the code from valuation_rules that applies (for example "NRV2"). Do not cite articles or rules outside the list.
- If something is missing (VAT rate, payment terms…), choose the most usual option and say so in "assumptions".
- Write for someone who is learning: short and clear. Write the texts in English, but keep Spanish account numbers.

Reply ONLY with a valid JSON object, with no text before or after:
{"explanation": "2 or 3 sentences: what the transaction is and how it is recorded",
 "valuation_rule": "NRV…",
 "partner_name": "third party name if the student mentions one, or empty",
 "assumptions": ["assumptions you made"],
 "lines": [{"account": "217", "side": "debit", "amount": 1200, "role": "base", "description": "why this account, briefly"}],
 "question": "a short question so the student can check they understood"}`,
}

const REPAIR = {
  es: (checks) => `El ERP ha encontrado estos errores en tu asiento: ${checks}. Corrígelo y responde de nuevo SOLO con el JSON completo.`,
  en: (checks) => `The ERP found these errors in your entry: ${checks}. Fix it and reply again ONLY with the complete JSON.`,
}

const responseText = (out) =>
  typeof out?.response === 'string' ? out.response
    : typeof out?.response === 'object' && out.response ? JSON.stringify(out.response)
    : out?.choices?.[0]?.message?.content ?? ''

// Propuesta del modelo: el primer objeto JSON del texto, con las líneas mínimamente saneadas
export function parseProposal(text) {
  if (!text) return null
  const start = text.indexOf('{')
  const end = text.lastIndexOf('}')
  if (start < 0 || end <= start) return null
  try {
    const p = JSON.parse(text.slice(start, end + 1))
    if (!Array.isArray(p.lines)) return null
    const str = (v) => (typeof v === 'string' ? v.trim() : '')
    return {
      explanation: str(p.explanation),
      valuation_rule: str(p.valuation_rule).toUpperCase().replace(/[^A-Z0-9]/g, ''),
      partner_name: str(p.partner_name),
      assumptions: Array.isArray(p.assumptions) ? p.assumptions.filter((x) => typeof x === 'string').slice(0, 5) : [],
      question: str(p.question),
      lines: p.lines.slice(0, 20).map((l) => ({
        account: String(l?.account ?? '').replace(/\D/g, ''),
        side: l?.side === 'credit' ? 'credit' : l?.side === 'debit' ? 'debit' : String(l?.side ?? ''),
        amount: Number(l?.amount),
        role: str(l?.role) || 'other',
        tax_code: str(l?.tax_code) || undefined,
        tax_base: l?.tax_base == null ? undefined : Number(l.tax_base),
        description: str(l?.description).slice(0, 200),
      })),
    }
  } catch {
    return null
  }
}

async function rpc(env, auth, fn, args) {
  const res = await fetch(`${env.VITE_SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: {
      apikey: env.VITE_SUPABASE_KEY, Authorization: auth,
      'Content-Type': 'application/json', 'Content-Profile': 'erp', 'Accept-Profile': 'erp',
    },
    body: JSON.stringify(args),
  })
  const body = await res.json().catch(() => ({}))
  return { ok: res.ok, status: res.status, body }
}

export async function onRequestGet({ env }) {
  return json({ ok: true, ai: Boolean(env.AI), supabase: Boolean(env.VITE_SUPABASE_URL && env.VITE_SUPABASE_KEY),
                model: env.AI_MODEL || DEFAULT_MODEL })
}

export async function onRequestPost({ request, env }) {
  if (!env.AI) return json({ error: 'ai_not_configured' }, 500)
  if (!env.VITE_SUPABASE_URL || !env.VITE_SUPABASE_KEY) return json({ error: 'supabase_not_configured' }, 500)
  const auth = request.headers.get('Authorization') ?? ''
  if (!auth.startsWith('Bearer ')) return json({ error: 'not_signed_in' }, 401)

  let body
  try { body = await request.json() } catch { return json({ error: 'bad_request' }, 400) }
  const language = body.language === 'en' ? 'en' : 'es'
  const text = typeof body.text === 'string' ? body.text.trim().slice(0, MAX_TEXT) : ''
  if (!body.company_id || text.length < 5) return json({ error: 'bad_request' }, 400)

  const ctx = await rpc(env, auth, 'entry_tutor_context', { p_company: body.company_id, p_language: language })
  if (!ctx.ok) return json({ error: 'context_denied', detail: ctx.body?.message ?? '' }, ctx.status === 401 ? 401 : 403)

  const model = env.AI_MODEL || DEFAULT_MODEL
  const messages = [
    { role: 'system', content: INSTRUCTIONS[language] },
    { role: 'user', content: `${JSON.stringify(ctx.body)}\n\n---\n${language === 'en' ? 'Transaction' : 'Operación'}: ${text}` },
  ]

  let proposal = null
  let validation = null
  let rounds = 0
  for (; rounds < 2; rounds++) {
    let out
    try {
      out = await env.AI.run(model, { messages, max_tokens: 1200, temperature: 0.1 })
    } catch (e) {
      const quota = /limit|quota|neuron|429/i.test(String(e?.message ?? e))
      return json({ error: quota ? 'ai_quota' : 'ai_failed', detail: String(e?.message ?? e).slice(0, 300) }, quota ? 429 : 502)
    }
    const answer = responseText(out)
    proposal = parseProposal(answer)
    if (!proposal) {
      if (rounds === 0) { messages.push({ role: 'assistant', content: answer }, { role: 'user', content: REPAIR[language]('not valid JSON') }); continue }
      return json({ error: 'ai_bad_answer', raw: answer.slice(0, 3000), model }, 502)
    }
    const v = await rpc(env, auth, 'validate_proposed_entry', {
      p_company: body.company_id,
      p_proposal: { partner_name: proposal.partner_name, valuation_rule: proposal.valuation_rule || undefined, lines: proposal.lines },
    })
    if (!v.ok) return json({ error: 'validation_failed', detail: v.body?.message ?? '' }, 502)
    validation = v.body
    if (validation.ok) break
    // Segunda vuelta: se le enseñan los errores del ERP
    const errors = validation.checks.filter((c) => c.level === 'error').map((c) => `${c.code} ${c.detail ?? ''}`.trim()).join('; ')
    messages.push({ role: 'assistant', content: answer }, { role: 'user', content: REPAIR[language](errors) })
  }

  const rule = (ctx.body.valuation_rules ?? []).find((r) => r.code === proposal.valuation_rule)
  return json({
    model, rounds: Math.min(rounds + 1, 2),
    proposal: { ...proposal, valuation_rule_title: rule?.title ?? null },
    validation,
  })
}
