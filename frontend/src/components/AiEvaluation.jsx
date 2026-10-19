import { useEffect, useRef, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { STOP_ERRORS, aiQueue, aiSummary, tutorAnswer } from '../practice'

// EVALUAR LA IA (v0.40.0): el Tutor de asientos resuelve los supuestos con su enunciado, como si se lo escribieras tú,
// y erp.submit_exercise lo corrige igual que a una persona (by = 'ai', con el modelo que contestó). Así se mide la IA
// con casos de solución conocida, antes de fiarse de ella. Gasta una consulta de IA por supuesto (con la cuota de
// la empresa elegida) y solo funciona en la web publicada (Cloudflare), como el Tutor.
export default function AiEvaluation({ exercises, progress, onDone }) {
  const { t, language } = useI18n()
  const [companies, setCompanies] = useState(null)
  const [companyId, setCompanyId] = useState('')
  const [status, setStatus] = useState(null)   // ai_status de la empresa elegida
  const [run, setRun] = useState(null)         // { done, total, title } mientras resuelve
  const [log, setLog] = useState([])           // [{ key, score, ok, error }]
  const [error, setError] = useState('')
  const stop = useRef(false)
  const tr = (x, f) => (language === 'en' ? x[`${f}_en`] || x[f] : x[f])

  useEffect(() => {
    supabase.from('v_my_companies').select('id, name, tax_territory').order('name').then(({ data }) => {
      setCompanies(data ?? [])
      if (data?.length) setCompanyId(data[0].id)
    })
  }, [])
  useEffect(() => {
    if (!companyId) return
    let alive = true
    supabase.rpc('ai_status', { p_company: companyId }).then(({ data }) => { if (alive) setStatus(data ?? { allowed: false }) })
    return () => { alive = false }
  }, [companyId, run === null])   // eslint-disable-line react-hooks/exhaustive-deps

  const company = companies?.find((c) => c.id === companyId)
  const remaining = status?.limit == null ? null : Math.max(0, status.limit - status.used)
  const { fit, queue: todo } = aiQueue(exercises, progress, company, remaining)
  const s = aiSummary(progress)
  const results = progress.filter((r) => r.ai_score != null).sort((a, b) => a.sort - b.sort)

  async function evaluate() {
    stop.current = false; setError(''); setLog([])
    const { data: { session } } = await supabase.auth.getSession()
    for (let i = 0; i < todo.length; i++) {
      if (stop.current) break
      const x = todo[i]
      setRun({ done: i, total: todo.length, title: tr(x, 'title') })
      let item
      try {
        const res = await fetch('/api/tutor', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${session?.access_token ?? ''}` },
          body: JSON.stringify({ company_id: companyId, text: tr(x, 'statement'), language }),
        })
        if (res.status === 404 || !(res.headers.get('content-type') ?? '').includes('json')) { setError(t('aiNotAvailableLocally')); break }
        const body = await res.json()
        if (!res.ok) {
          if (STOP_ERRORS.includes(body.error)) { setError(t(`aiError.${body.error}`)); break }
          item = { key: x.key, error: t(`aiError.${body.error}`) }
        } else {
          const { data: g, error: e } = await supabase.rpc('submit_exercise', { p_key: x.key, p_answer: tutorAnswer(body.validation), p_by: 'ai', p_model: body.model ?? null })
          item = e ? { key: x.key, error: e.message } : { key: x.key, score: g.score, ok: g.ok }
        }
      } catch (e) {
        item = { key: x.key, error: e.message }
      }
      setLog((l) => [...l, item])
    }
    setRun(null)
    onDone()
  }

  const title = (key) => { const x = exercises.find((e) => e.key === key); return x ? tr(x, 'title') : key }

  return (
    <section className="evaluar-ia" aria-labelledby="evaluar-ia-titulo">
      <h3 id="evaluar-ia-titulo">🤖 {t('pr.ai.title')}</h3>
      <p className="ayuda">{t('pr.ai.intro')}</p>
      {companies === null ? null : companies.length === 0 ? <p className="aviso">{t('pr.ai.noCompany')}</p> : (
        <>
          <div className="fila fila-evaluar">
            <label>{t('pr.ai.company')}
              <select value={companyId} disabled={Boolean(run)} onChange={(e) => setCompanyId(e.target.value)}>
                {companies.map((c) => <option key={c.id} value={c.id}>{c.name} · {t(`territory.${c.tax_territory}`)}</option>)}
              </select>
            </label>
            {run
              ? <button type="button" className="secundario" onClick={() => { stop.current = true }}>■ {t('pr.ai.stop')}</button>
              : <button type="button" disabled={!status?.allowed || remaining === 0 || todo.length === 0} onClick={evaluate}>
                  ▶ {t('pr.ai.run').replace('{n}', todo.length)}
                </button>}
          </div>
          {status && !status.allowed && <p className="aviso">{t('pr.ai.notAllowed')}</p>}
          {status?.allowed && (
            <p className="ayuda">
              {t('pr.ai.cost').replace('{n}', todo.length)}
              {remaining !== null && <> · {t('aiRemaining').replace('{n}', remaining).replace('{l}', status.limit)}</>}
              {fit < exercises.length && <> · {t('pr.ai.skipped').replace('{n}', exercises.length - fit)}</>}
              {todo.length < fit && <> · {t('pr.ai.partial').replace('{n}', todo.length).replace('{m}', fit)}</>}
            </p>
          )}
        </>
      )}
      {run && (
        <div className="progreso-practica" role="status">
          <progress max={run.total} value={run.done} aria-label={t('pr.ai.title')} />
          <span>{t('pr.ai.running').replace('{i}', run.done + 1).replace('{n}', run.total).replace('{x}', run.title)}…</span>
        </div>
      )}
      {error && <p className="aviso" role="alert">⚠ {error}</p>}
      {log.some((l) => l.error) && (
        <ul className="comprobaciones">
          {log.filter((l) => l.error).map((l) => <li key={l.key} className="warning"><span className="icono">⚠</span> {title(l.key)}: {l.error}</li>)}
        </ul>
      )}

      {results.length > 0 && (
        <>
          <p className="resumen-ia-evaluacion">
            {t('pr.ai.summary').replace('{a}', s.aiSolved).replace('{e}', s.evaluated).replace('{m}', s.aiAvg).replace('{u}', s.userSolved)}
          </p>
          <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('pr.ai.title')}>
            <table className="informe">
              <thead><tr><th scope="col">{t('pr.ai.case')}</th><th scope="col" className="num">{t('pr.ai.colAi')}</th><th scope="col" className="num">{t('pr.ai.colYou')}</th></tr></thead>
              <tbody>
                {results.map((r) => (
                  <tr key={r.key}>
                    <td><a className="enlace" href={`#/practicar/${r.key}`}>{tr(r, 'title')}</a></td>
                    <td className="num">{r.ai_ok ? '✓' : '✕'} {r.ai_score} %</td>
                    <td className="num">{Number(r.attempts) > 0 ? `${r.solved ? '✓' : '✕'} ${r.best_score} %` : '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {s.models.length > 0 && <p className="ayuda">{t('pr.ai.models').replace('{m}', s.models.map((m) => m.replace(/^@cf\//, '')).join(', '))}</p>}
          <p className="ayuda">{t('pr.ai.note')}</p>
        </>
      )}
    </section>
  )
}
