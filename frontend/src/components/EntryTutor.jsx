import { useEffect, useRef, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import AiFeedback from './AiFeedback'
import { money } from '../format'
import { companyPath } from '../router'
import Link from './Link'
import ErrorBox from './ErrorBox'
import { addMessage, sendsOnKey, updateMessage } from '../aiPanel'

// Tutor de asientos con IA: describes la operación, la IA propone el asiento, el ERP lo comprueba y tú decides.
// v0.41.2: es una conversación dentro del panel de IA (abajo a la derecha). «Pasar al asiento» crea las subcuentas
// nuevas que hagan falta y lleva las líneas al formulario de Nuevo asiento: nada se contabiliza sin que lo revises.
// Lo ven el propietario y el titular de los datos (erp.ai_status, con cuota diaria). La conversación no se guarda.
export default function EntryTutor({ company, onLoad }) {
  const { t, language } = useI18n()
  const [allowed, setAllowed] = useState(false)
  const [text, setText] = useState('')
  const [msgs, setMsgs] = useState([])   // [{ id, text, result, where, error }] · las últimas 20, solo en memoria
  const [busy, setBusy] = useState(false)
  const [loading, setLoading] = useState(null)   // id del mensaje que se está pasando al asiento
  const [loaded, setLoaded] = useState(null)     // id del último que se pasó
  const endRef = useRef(null)

  const [status, setStatus] = useState(null)   // { allowed, used, limit } · limit null = sin límite (el owner)
  // ¿Puede usar la IA en ESTA empresa? El owner, o el titular de los datos (Miembro) con su cuota diaria
  const loadStatus = () => supabase.rpc('ai_status', { p_company: company.id })
    .then(({ data }) => { setStatus(data); setAllowed(data?.allowed === true) })
  useEffect(() => { loadStatus() }, [company.id])
  const remaining = status?.limit == null ? null : Math.max(0, status.limit - status.used)
  useEffect(() => { setMsgs([]) }, [company.id])   // otra empresa: otra conversación
  useEffect(() => { endRef.current?.scrollIntoView?.({ block: 'end' }) }, [msgs.length, busy])

  async function propose() {
    const question = text.trim()
    if (question.length < 5 || busy) return
    const id = Date.now()
    setMsgs((m) => addMessage(m, { id, text: question }))
    setText(''); setBusy(true)
    try {
      const { data: { session } } = await supabase.auth.getSession()
      const res = await fetch('/api/tutor', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${session?.access_token ?? ''}` },
        body: JSON.stringify({ company_id: company.id, text: question, language }),
      })
      if (res.status === 404 || !(res.headers.get('content-type') ?? '').includes('json')) {
        throw new Error(t('aiNotAvailableLocally'))
      }
      const body = await res.json()
      if (!res.ok) throw new Error(t(`aiError.${body.error}`) + (body.detail ? ` (${body.detail})` : ''))
      setMsgs((m) => updateMessage(m, id, { result: body }))
      // ¿Dónde se registra en el ERP? (si la base de datos aún no tiene el catálogo, no se enseña)
      const lines = body.validation?.lines ?? []
      supabase.rpc('operation_for_lines', { p_lines: lines.map((l) => ({ account_no: l.account_no, debit: l.debit, credit: l.credit })) })
        .then(({ data }) => setMsgs((m) => updateMessage(m, id, { where: Array.isArray(data) ? data[0] ?? null : null })))
    } catch (e) {
      setMsgs((m) => updateMessage(m, id, { error: e.message }))
    } finally {
      setBusy(false)
      loadStatus()
    }
  }

  // Crea las subcuentas nuevas (217 → 21700001…) y pasa el asiento al formulario de Nuevo asiento
  async function load(msg) {
    setLoading(msg.id)
    const v = msg.result.validation
    for (const l of v.lines.filter((x) => x.new_account)) {
      const { error } = await supabase.rpc('create_posting_account', {
        p_company: company.id, p_account_no: l.account_no, p_name: l.account_name,
      })
      // Si ya existe (dos líneas con la misma cuenta nueva), no pasa nada
      if (error && !/duplicate|already exists|ya existe/i.test(error.message)) {
        setLoading(null)
        return setMsgs((m) => updateMessage(m, msg.id, { error: error.message }))
      }
    }
    setLoading(null); setLoaded(msg.id)
    onLoad({
      id: Date.now(),
      description: msg.text.slice(0, 120),
      lines: v.lines.map((l) => ({ account_no: l.account_no, debit: l.debit, credit: l.credit, description: l.description })),
    })
  }

  if (!allowed) return <p className="ayuda">{t('aiPanelNotAllowed')}</p>

  return (
    <div className="chat-ia">
      <p className="ayuda">{t('tutorIntro')}</p>
      <ol className="chat-mensajes" aria-live="polite">
        {msgs.map((msg) => (
          <li key={msg.id} className="chat-turno">
            <p className="burbuja usuario"><span className="oculto">{t('aiYou')}: </span>{msg.text}</p>
            {msg.error && <div className="burbuja ia"><ErrorBox error={msg.error} company={company} /></div>}
            {!msg.result && !msg.error && <p className="burbuja ia escribiendo">{t('tutorThinking')}… <small>{t('aiWait')}</small></p>}
            {msg.result && (
              <div className="burbuja ia">
                <Proposal company={company} msg={msg} t={t} language={language}
                          loading={loading === msg.id} loaded={loaded === msg.id} onLoad={() => load(msg)} />
              </div>
            )}
          </li>
        ))}
        <li ref={endRef} aria-hidden="true" className="chat-fin" />
      </ol>
      {msgs.length === 0 && <p className="ayuda chat-vacio">💬 {t('tutorPlaceholder')}</p>}
      <form className="chat-entrada" onSubmit={(e) => { e.preventDefault(); propose() }}>
        <label className="oculto" htmlFor="tutor-pregunta">{t('tutorTitle')}</label>
        <textarea id="tutor-pregunta" rows={2} maxLength={1000} value={text} placeholder={t('aiPanelAsk')}
                  onChange={(e) => setText(e.target.value)}
                  onKeyDown={(e) => { if (sendsOnKey(e)) { e.preventDefault(); propose() } }} />
        <button type="submit" disabled={busy || text.trim().length < 5 || remaining === 0}>
          {busy ? `${t('tutorThinking')}…` : t('tutorPropose')}
        </button>
      </form>
      {remaining !== null && <p className="ayuda">{t('aiRemaining').replace('{n}', remaining).replace('{l}', status.limit)}</p>}
    </div>
  )
}

// La respuesta del Tutor: explicación, asiento comprobado por el ERP, avisos, dónde se registra y «Pasar al asiento»
function Proposal({ company, msg, t, language, loading, loaded, onLoad }) {
  const { result, where } = msg
  const p = result.proposal
  const v = result.validation
  const m = (x) => money(x, language)
  const icon = { error: '✕', warning: '⚠', info: 'ℹ' }
  if (!p || !v) return null
  return (
    <div className="propuesta">
      {p.explanation && <p className="resumen-ia">{p.explanation}</p>}
      {p.valuation_rule_title && <p><span className="etiqueta">📘 {p.valuation_rule_title}</span></p>}
      {p.assumptions.length > 0 && (
        <div className="bloque-ia">
          <h3>{t('tutorAssumptions')}</h3>
          <ul>{p.assumptions.map((a, i) => <li key={i}><span className="icono">•</span> {a}</li>)}</ul>
        </div>
      )}

      <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('tutorProposedEntry')}>
        <table className="informe">
          <thead>
            <tr><th>{t('account')}</th><th className="num">{t('debit')}</th><th className="num">{t('credit')}</th></tr>
          </thead>
          <tbody>
            {v.lines.map((l) => (
              <tr key={l.line_no} title={l.description || undefined}>
                <td>
                  <span className="codigo">{l.account_no}</span> {l.account_name}
                  {l.new_account && <span className="insignia">{t('tutorNewAccount')}</span>}
                  {l.description && <small className="porque">{l.description}</small>}
                </td>
                <td className="num">{Number(l.debit) ? m(l.debit) : ''}</td>
                <td className="num">{Number(l.credit) ? m(l.credit) : ''}</td>
              </tr>
            ))}
            <tr className="total">
              <td><strong>{t('total')}</strong></td>
              <td className="num"><strong>{m(v.debit)}</strong></td>
              <td className="num"><strong>{m(v.credit)}</strong></td>
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
      {where && (
        <p className="donde-registra">
          📍 {t('tutorWhere')}: <strong>{language === 'en' ? where.title_en || where.title : where.title}</strong>
          {where.screen !== 'entry' && (<> → <Link to={companyPath(company.id, where.screen)} className="enlace">
            {t(`nav.${where.screen}.label`).replace('{tax}', company.tax_territory === 'canary_islands' ? 'IGIC' : 'IVA').replace('{form}', company.tax_territory === 'canary_islands' ? '420' : '303')}</Link></>)}
          <small>{t(where.screen === 'entry' ? 'tutorWhereHere' : 'tutorWhereScreen')}</small>
        </p>
      )}
      {result.rounds === 2 && <p className="ayuda">↻ {t('tutorSecondRound')}</p>}

      {p.question && (
        <div className="bloque-ia learning">
          <h3>❓ {t('tutorQuestion')}</h3>
          <p>{p.question}</p>
        </div>
      )}

      {v.ok
        ? <button type="button" disabled={loading} onClick={onLoad}>⬇ {t('tutorLoad')}</button>
        : <p className="aviso">⚠ {t('tutorCannotLoad')}</p>}
      {loaded && <p className="exito" role="status">✓ {t('tutorLoadedPanel')}</p>}
      <p className="ayuda">{t('tutorDisclaimer').replace('{m}', result.model.replace(/^@cf\//, ''))}</p>
      <AiFeedback key={p.explanation ?? ''} company={company} kind="tutor" prompt={msg.text} model={result.model}
                  answer={{ explanation: p.explanation, valuation_rule: p.valuation_rule, assumptions: p.assumptions,
                            lines: v.lines, checks: v.checks, ok: v.ok }} />
    </div>
  )
}
