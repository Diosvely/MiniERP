import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import AiFeedback from './AiFeedback'
import { money } from '../format'

// Tutor de asientos con IA: describes la operación, la IA propone el asiento, el ERP lo comprueba y tú decides.
// "Cargar en el asiento" crea las subcuentas nuevas que hagan falta y pasa las líneas al formulario de abajo:
// nada se contabiliza sin que lo revises. Lo ven el propietario y el titular de los datos (erp.ai_status, con cuota diaria).
export default function EntryTutor({ company, onLoad }) {
  const { t, language } = useI18n()
  const [allowed, setAllowed] = useState(false)
  const [text, setText] = useState('')
  const [result, setResult] = useState(null)
  const [busy, setBusy] = useState(false)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  const [status, setStatus] = useState(null)   // { allowed, used, limit } · limit null = sin límite (el owner)
  // ¿Puede usar la IA en ESTA empresa? El owner, o el titular de los datos (Miembro) con su cuota diaria
  const loadStatus = () => supabase.rpc('ai_status', { p_company: company.id })
    .then(({ data }) => { setStatus(data); setAllowed(data?.allowed === true) })
  useEffect(() => { loadStatus() }, [company.id])
  const remaining = status?.limit == null ? null : Math.max(0, status.limit - status.used)
  useEffect(() => { setResult(null); setError('') }, [company.id])

  const m = (v) => money(v, language)

  async function propose() {
    setBusy(true); setError(''); setResult(null)
    try {
      const { data: { session } } = await supabase.auth.getSession()
      const res = await fetch('/api/tutor', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${session?.access_token ?? ''}` },
        body: JSON.stringify({ company_id: company.id, text, language }),
      })
      if (res.status === 404 || !(res.headers.get('content-type') ?? '').includes('json')) {
        throw new Error(t('aiNotAvailableLocally'))
      }
      const body = await res.json()
      if (!res.ok) throw new Error(t(`aiError.${body.error}`) + (body.detail ? ` (${body.detail})` : ''))
      setResult(body)
    } catch (e) {
      setError(e.message)
    } finally {
      setBusy(false)
      loadStatus()
    }
  }

  // Crea las subcuentas nuevas (217 → 21700001…) y pasa el asiento al formulario
  async function load() {
    setLoading(true); setError('')
    const v = result.validation
    for (const l of v.lines.filter((x) => x.new_account)) {
      const { error } = await supabase.rpc('create_posting_account', {
        p_company: company.id, p_account_no: l.account_no, p_name: l.account_name,
      })
      // Si ya existe (dos líneas con la misma cuenta nueva), no pasa nada
      if (error && !/duplicate|already exists|ya existe/i.test(error.message)) {
        setLoading(false)
        return setError(error.message)
      }
    }
    setLoading(false)
    onLoad({
      id: Date.now(),
      description: text.slice(0, 120),
      lines: v.lines.map((l) => ({ account_no: l.account_no, debit: l.debit, credit: l.credit, description: l.description })),
    })
    window.scrollTo?.({ top: document.querySelector('.formulario-asiento')?.offsetTop ?? 0, behavior: 'smooth' })
  }

  if (!allowed) return null
  const p = result?.proposal
  const v = result?.validation
  const icon = { error: '✕', warning: '⚠', info: 'ℹ' }

  return (
    <section className="tarjeta tutor-asientos">
      <h2>🎓 {t('tutorTitle')}</h2>
      <p className="ayuda">{t('tutorIntro')}</p>
      <textarea rows={3} maxLength={1000} value={text} placeholder={t('tutorPlaceholder')}
                onChange={(e) => setText(e.target.value)} />
      <button type="button" disabled={busy || text.trim().length < 5 || remaining === 0} onClick={propose}>
        {busy ? `${t('tutorThinking')}…` : t('tutorPropose')}
      </button>
      {busy && <p className="ayuda">{t('aiWait')}</p>}
      {remaining !== null && <p className="ayuda">{t('aiRemaining').replace('{n}', remaining).replace('{l}', status.limit)}</p>}
      {error && <p className="aviso">⚠ {error}</p>}

      {p && v && (
        <div className="propuesta">
          {p.explanation && <p className="resumen-ia">{p.explanation}</p>}
          {p.valuation_rule_title && <p><span className="etiqueta">📘 {p.valuation_rule_title}</span></p>}
          {p.assumptions.length > 0 && (
            <div className="bloque-ia">
              <h3>{t('tutorAssumptions')}</h3>
              <ul>{p.assumptions.map((a, i) => <li key={i}><span className="icono">•</span> {a}</li>)}</ul>
            </div>
          )}

          <div className="tabla-ancha">
            <table className="informe">
              <thead>
                <tr><th>{t('account')}</th><th className="num">{t('debit')}</th><th className="num">{t('credit')}</th><th>{t('tutorWhy')}</th></tr>
              </thead>
              <tbody>
                {v.lines.map((l) => (
                  <tr key={l.line_no}>
                    <td>
                      <span className="codigo">{l.account_no}</span> {l.account_name}
                      {l.new_account && <span className="insignia">{t('tutorNewAccount')}</span>}
                    </td>
                    <td className="num">{Number(l.debit) ? m(l.debit) : ''}</td>
                    <td className="num">{Number(l.credit) ? m(l.credit) : ''}</td>
                    <td className="ayuda">{l.description}</td>
                  </tr>
                ))}
                <tr className="total">
                  <td><strong>{t('total')}</strong></td>
                  <td className="num"><strong>{m(v.debit)}</strong></td>
                  <td className="num"><strong>{m(v.credit)}</strong></td>
                  <td />
                </tr>
              </tbody>
            </table>
          </div>

          {v.checks.length > 0 && (
            <>
              <h3>{t('tutorChecks')}</h3>
              <ul className="comprobaciones">
                {v.checks.map((c, i) => (
                  <li key={i} className={c.level}>
                    <span className="icono">{icon[c.level]}</span> {t(`tutorCheck.${c.code}`).replace('{d}', c.detail ?? '')}
                  </li>
                ))}
              </ul>
            </>
          )}
          {result.rounds === 2 && <p className="ayuda">↻ {t('tutorSecondRound')}</p>}

          {p.question && (
            <div className="bloque-ia learning">
              <h3>❓ {t('tutorQuestion')}</h3>
              <p>{p.question}</p>
            </div>
          )}

          {v.ok
            ? <button type="button" disabled={loading} onClick={load}>⬇ {t('tutorLoad')}</button>
            : <p className="aviso">⚠ {t('tutorCannotLoad')}</p>}
          <p className="ayuda">{t('tutorDisclaimer').replace('{m}', result.model.replace(/^@cf\//, ''))}</p>
          <AiFeedback key={result.proposal?.explanation ?? ''} company={company} kind="tutor" prompt={text} model={result.model}
                      answer={{ explanation: p.explanation, valuation_rule: p.valuation_rule, assumptions: p.assumptions,
                                lines: v.lines, checks: v.checks, ok: v.ok }} />
        </div>
      )}
    </section>
  )
}
