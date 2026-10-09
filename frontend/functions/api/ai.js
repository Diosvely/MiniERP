// =====================================================================
// ANALISTA IA · Cloudflare Pages Function  →  POST /api/ai
// ---------------------------------------------------------------------
// 1. Recibe la sesión de Supabase del usuario (cabecera Authorization) y { company_id, year, language }.
// 2. Pide a Supabase el resumen de la empresa (erp.ai_context) CON LA SESIÓN DEL USUARIO:
//    la base de datos comprueba que es el owner y que puede leer la empresa (RLS). Aquí no hay claves secretas.
// 3. Se lo pasa a un modelo open source de Cloudflare Workers AI (binding "AI": sin clave de API)
//    con instrucciones de auditor: interpretar las cifras, no recalcularlas.
// 4. Devuelve el análisis en JSON: resumen, fortalezas, alertas, preguntas del auditor y una idea para aprender.
//
// Configuración en Cloudflare Pages (Settings):
//   · Bindings → Workers AI → nombre AI            (Producción y Vista previa)
//   · Variables VITE_SUPABASE_URL y VITE_SUPABASE_KEY (ya existen para el build; las Functions también las leen)
//   · Opcional: AI_MODEL para probar otro modelo sin tocar el código
// =====================================================================

// Mistral Small 3.1: buen español, ~190 neuronas por análisis → unos 50 análisis al día gratis
const DEFAULT_MODEL = '@cf/mistralai/mistral-small-3.1-24b-instruct'

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json; charset=utf-8' } })

const INSTRUCTIONS = {
  es: `Eres un auditor y profesor de contabilidad española (PGC PYMES). Analizas una empresa a partir de un resumen
en JSON que ha calculado un ERP: balance, cuenta de pérdidas y ganancias, estado de flujos de efectivo y ratios.
Las cifras YA están calculadas y cuadradas.

Reglas:
- Usa SOLO los datos del JSON. No inventes cifras ni supongas datos que no están.
- No recalcules: cita los valores tal como vienen, ya redondeados (con el año anterior cuando ayude a ver la evolución).
  Los ratios con unit "percent" ya están en % (10.7 → 10,7 %); los de unit "days" son días.
- Un ratio sin "value" no se puede calcular (por ejemplo, la calidad del resultado con pérdidas): no lo comentes.
- Un ratio fuera de su zona de referencia (status "low" o "high") es una PREGUNTA, no una conclusión: depende del sector.
- Si "lower_is_safer" es true, estar por debajo de la zona significa MENOS riesgo: no lo pongas como alerta
  (un endeudamiento bajo no es un problema; como mucho, una pregunta sobre si se aprovecha la financiación).
- Un punto fuerte nunca puede contradecir los datos: con pérdidas o con flujo de explotación negativo,
  no presentes como bueno un ratio que dependa de ellos.
- Si cash_flow_check.cross_count > 0, explica que hay asientos sin dinero que mezclan actividades
  (por ejemplo, inmovilizado comprado a un proveedor 400 en lugar de a la 523).
- Escribe para alguien que está aprendiendo: claro, concreto y sin relleno.
- Importes en euros con formato español (1.234,56 €) y porcentajes con coma (7,6 %).

Responde SOLO con un objeto JSON válido, sin texto antes ni después, con esta forma:
{"summary": "3 o 4 frases con la situación general",
 "strengths": ["hasta 4 puntos fuertes, cada uno con su cifra"],
 "alerts": ["hasta 4 alertas, cada una con su cifra y por qué importa"],
 "auditor_questions": ["hasta 4 preguntas que haría un auditor a la empresa"],
 "learning": "una idea de contabilidad o de análisis que se aprende con este caso"}`,
  en: `You are an auditor and teacher of Spanish accounting (Spanish GAAP, SME model). You analyse a company from a JSON
summary calculated by an ERP: balance sheet, profit and loss account, cash flow statement and ratios.
The figures are ALREADY calculated and reconciled.

Rules:
- Use ONLY the data in the JSON. Do not invent figures or assume data that is not there.
- Do not recalculate: quote the values as given, already rounded (with the previous year when it helps show the trend).
  Ratios with unit "percent" are already in % (10.7 → 10.7 %); unit "days" means days.
- A ratio with no "value" cannot be calculated (for example, quality of earnings with a loss): do not comment on it.
- A ratio outside its reference range (status "low" or "high") is a QUESTION, not a conclusion: it depends on the industry.
- If "lower_is_safer" is true, being below the range means LESS risk: do not list it as an alert
  (low debt is not a problem; at most, a question about whether financing is being used well).
- A strength must never contradict the data: with a loss or negative operating cash flow,
  do not present as good a ratio that depends on them.
- If cash_flow_check.cross_count > 0, explain that there are non-cash entries mixing activities
  (for example, a fixed asset bought from a 400 supplier instead of account 523).
- Write for someone who is learning: clear, concrete and without filler.
- Amounts in euros (1,234.56 €) and percentages with a point (7.6 %).

Reply ONLY with a valid JSON object, with no text before or after it, in this shape:
{"summary": "3 or 4 sentences on the overall situation",
 "strengths": ["up to 4 strengths, each with its figure"],
 "alerts": ["up to 4 alerts, each with its figure and why it matters"],
 "auditor_questions": ["up to 4 questions an auditor would ask the company"],
 "learning": "one accounting or analysis idea learned from this case"}`,
}

// Los modelos a veces envuelven el JSON en ```json … ``` o añaden una frase: se extrae el primer objeto
export function parseAnalysis(text) {
  if (!text) return null
  const start = text.indexOf('{')
  const end = text.lastIndexOf('}')
  if (start < 0 || end <= start) return null
  try {
    const a = JSON.parse(text.slice(start, end + 1))
    const list = (v) => (Array.isArray(v) ? v.filter((x) => typeof x === 'string' && x.trim()).slice(0, 4) : [])
    if (typeof a.summary !== 'string') return null
    return {
      summary: a.summary, strengths: list(a.strengths), alerts: list(a.alerts),
      auditor_questions: list(a.auditor_questions), learning: typeof a.learning === 'string' ? a.learning : '',
    }
  } catch {
    return null
  }
}

// Texto de la respuesta según el formato del modelo ({ response } o al estilo OpenAI { choices })
const responseText = (out) =>
  typeof out?.response === 'string' ? out.response
    : typeof out?.response === 'object' && out.response ? JSON.stringify(out.response)
    : out?.choices?.[0]?.message?.content ?? ''

// GET /api/ai → comprobación de la configuración (no devuelve datos)
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
  const year = Number(body.year)
  if (!body.company_id || !Number.isInteger(year)) return json({ error: 'bad_request' }, 400)

  // Resumen de la empresa con la sesión del usuario: la base de datos decide si puede
  const ctx = await fetch(`${env.VITE_SUPABASE_URL}/rest/v1/rpc/ai_context`, {
    method: 'POST',
    headers: {
      apikey: env.VITE_SUPABASE_KEY, Authorization: auth,
      'Content-Type': 'application/json', 'Content-Profile': 'erp', 'Accept-Profile': 'erp',
    },
    body: JSON.stringify({ p_company: body.company_id, p_year: year, p_language: language }),
  })
  if (!ctx.ok) {
    const e = await ctx.json().catch(() => ({}))
    // PGRST202: la función no existe en Supabase → falta ejecutar la migración
    if (e.code === 'PGRST202' || ctx.status === 404) return json({ error: 'db_not_updated', detail: '0024' }, 500)
    const status = ctx.status === 401 ? 401 : 403
    return json({ error: 'context_denied', detail: e.message ?? '' }, status)
  }
  const context = await ctx.json()

  const model = env.AI_MODEL || DEFAULT_MODEL
  let out
  try {
    out = await env.AI.run(model, {
      messages: [
        { role: 'system', content: INSTRUCTIONS[language] },
        { role: 'user', content: JSON.stringify(context) },
      ],
      max_tokens: 1500,
      temperature: 0.2,
    })
  } catch (e) {
    // Límite diario gratuito agotado (se reinicia a las 00:00 UTC) u otro fallo del modelo
    const quota = /limit|quota|neuron|429/i.test(String(e?.message ?? e))
    return json({ error: quota ? 'ai_quota' : 'ai_failed', detail: String(e?.message ?? e).slice(0, 300) }, quota ? 429 : 502)
  }

  const text = responseText(out)
  const analysis = parseAnalysis(text)
  // Si el modelo no devolvió JSON válido, se muestra su texto tal cual (mejor que nada)
  return json({ model, year, analysis, raw: analysis ? null : text.slice(0, 6000) })
}
