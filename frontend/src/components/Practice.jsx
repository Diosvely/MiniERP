import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { money } from '../format'
import { navigate } from '../router'
import { LINE_STATUS, answerLines, answerTotals, emptyLine, exerciseState, extraLines, groupByLevel, nextExercise, progressSummary } from '../practice'
import { GraduationCap } from 'lucide-react'
import { ICON } from '../icons'
import Link from './Link'
import Term from './Term'
import Sources from './Sources'
import ErrorBox from './ErrorBox'
import Loading from './Loading'
import AiEvaluation from './AiEvaluation'

// PRACTICAR (#/practicar · v0.40.0): supuestos prácticos autocorregidos, como los de un manual de contabilidad.
//   · #/practicar          → la lista, por nivel, con tu progreso (resueltos, intentos, mejor nota)
//   · #/practicar/<clave>  → el enunciado; escribes el asiento y la base de datos lo corrige línea a línea
//     (cuenta por su grupo o subgrupo del PGC, lado e importe), explica los errores frecuentes y guarda el intento.
// La solución se puede ver en cualquier momento; con ella, la explicación, la norma (📘) y dónde se registra en el ERP.
export default function Practice({ exerciseKey }) {
  const { t } = useI18n()
  const [data, setData] = useState(null)   // { exercises, progress, operations }
  const [error, setError] = useState('')
  const [reload, setReload] = useState(0)

  useEffect(() => {
    let alive = true
    Promise.all([
      supabase.from('exercises').select('*').order('sort'),
      supabase.from('v_exercise_progress').select('*').order('sort'),
      supabase.from('operations').select('key, title, title_en, screen, entry, entry_en, concept, sources'),
    ]).then(([x, p, o]) => {
      if (!alive) return
      const bad = x.error ?? p.error ?? o.error
      if (bad) { setData({ exercises: [], progress: [], operations: [] }); return setError(bad.code === '42P01' || bad.code === 'PGRST205' ? t('pr.dbMissing') : bad.message) }
      setError('')
      setData({ exercises: x.data ?? [], progress: p.data ?? [], operations: o.data ?? [] })
    })
    return () => { alive = false }
  }, [reload])   // eslint-disable-line react-hooks/exhaustive-deps

  const exercise = exerciseKey && data?.exercises.find((x) => x.key === exerciseKey)
  return (
    <section className="tarjeta practicar">
      <div className="fila-glosario">
        <button type="button" className="secundario" onClick={() => (exerciseKey ? navigate('/practicar') : window.history.back())}>
          ← {exerciseKey ? t('pr.backList') : t('glossaryBack')}
        </button>
        <h2><GraduationCap {...ICON} /> <Term id="exercise">{t('practice')}</Term></h2>
      </div>
      <ErrorBox error={error} />
      {data === null ? <Loading /> : exercise
        ? <Exercise key={exercise.key} exercise={exercise} data={data} onSubmitted={() => setReload((r) => r + 1)} />
        : <ExerciseList data={data} missing={Boolean(exerciseKey)} onReload={() => setReload((r) => r + 1)} />}
    </section>
  )
}

function ExerciseList({ data, missing, onReload }) {
  const { t, language } = useI18n()
  const s = progressSummary(data.progress)
  const tr = (x, f) => (language === 'en' ? x[`${f}_en`] || x[f] : x[f])
  return (
    <>
      <p className="ayuda">{t('pr.intro')}</p>
      {missing && <p className="aviso">{t('pr.notFound')}</p>}
      {s.total > 0 && (
        <div className="progreso-practica">
          <progress max={s.total} value={s.solved} aria-label={t('pr.progress')} />
          <span>{t('pr.summary').replace('{s}', s.solved).replace('{n}', s.total).replace('{a}', s.attempted)}</span>
        </div>
      )}
      {groupByLevel(data.exercises, data.progress).map((g) => (
        <div key={g.level} className="nivel-practica">
          <h3>{t(`pr.level.${g.level}`)}</h3>
          <ul className="lista-supuestos">
            {g.items.map((x) => {
              const st = exerciseState(x.progress)
              return (
                <li key={x.key} className={st}>
                  <Link to={`/practicar/${x.key}`}>
                    <span className="estado-supuesto" aria-hidden="true">{st === 'solved' ? '✓' : st === 'tried' ? '◐' : '○'}</span>
                    <span className="titulo-supuesto">{tr(x, 'title')}</span>
                    {x.tax_type && <span className="etiqueta">{x.tax_type === 'IGIC' ? 'IGIC' : t('pr.vat')}</span>}
                    <small>
                      {t(`pr.state.${st}`)}
                      {Number(x.progress.attempts) > 0 && ` · ${t('pr.best').replace('{p}', x.progress.best_score)} · ${(Number(x.progress.attempts) === 1 ? t('pr.attempt1') : t('pr.attempts').replace('{n}', x.progress.attempts))}`}
                    </small>
                  </Link>
                </li>
              )
            })}
          </ul>
        </div>
      ))}
      {data.exercises.length > 0 && <AiEvaluation exercises={data.exercises} progress={data.progress} onDone={onReload} />}
    </>
  )
}

function Exercise({ exercise: x, data, onSubmitted }) {
  const { t, language } = useI18n()
  const [lines, setLines] = useState([emptyLine(), emptyLine()])
  const [result, setResult] = useState(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [showSolution, setShowSolution] = useState(false)
  const m = (v) => money(v, language)
  const tr = (o, f) => (language === 'en' ? o[`${f}_en`] || o[f] : o[f])
  const op = data.operations.find((o) => o.key === x.operation)
  const progress = data.progress.find((r) => r.key === x.key)
  const next = nextExercise(data.exercises, x.key, data.progress)
  const totals = answerTotals(lines)
  const side = (s) => t(s === 'debit' ? 'debit' : 'credit')
  const tax = x.tax_type === 'IGIC' ? { tax: 'IGIC', form: '420' } : { tax: 'IVA', form: '303' }
  const screen = op && t(`nav.${op.screen}.label`).replace('{tax}', tax.tax).replace('{form}', tax.form)

  const update = (i, field, value) => { setLines(lines.map((l, k) => (k === i ? { ...l, [field]: value } : l))); setResult(null) }

  async function submit() {
    setBusy(true); setError('')
    const { data: g, error } = await supabase.rpc('submit_exercise', { p_key: x.key, p_answer: answerLines(lines), p_by: 'user' })
    setBusy(false)
    if (error) return setError(error.message)
    setResult(g)
    onSubmitted()
  }

  function retry() { setLines([emptyLine(), emptyLine()]); setResult(null); setShowSolution(false) }

  return (
    <div className="supuesto">
      <div className="titulo-modelo">
        <h3>{tr(x, 'title')}</h3>
        <span className="etiqueta">{t(`pr.level.${x.level}`)}</span>
        {x.tax_type && <span className="etiqueta">{x.tax_type === 'IGIC' ? 'IGIC' : t('pr.vat')}</span>}
        <Sources ids={x.sources} />
      </div>
      <p className="enunciado">{tr(x, 'statement')}</p>
      <p className="ayuda">
        {x.concept && <>{t('pr.concept')}: <Term id={x.concept} /> · </>}
        {t('pr.howTo')}
      </p>
      {progress?.ai_score != null && (
        <p className="ayuda">🤖 {t('pr.ai.oneCase').replace('{p}', progress.ai_score).replace('{r}', t(progress.ai_ok ? 'pr.ai.right' : 'pr.ai.wrong'))
          .replace('{m}', String(progress.ai_model ?? '').replace(/^@cf\//, ''))}</p>
      )}
      {progress && Number(progress.attempts) > 0 && (
        <p className="ayuda">{t(progress.solved ? 'pr.alreadySolved' : 'pr.triedBefore').replace('{n}', progress.attempts).replace('{p}', progress.best_score)}</p>
      )}

      <form className="respuesta-supuesto" onSubmit={(e) => { e.preventDefault(); submit() }}>
        <div className="lineas-respuesta" role="group" aria-label={t('pr.answer')}>
          <div className="linea-respuesta cabecera-respuesta" aria-hidden="true">
            <span>{t('account')}</span><span>{t('debit')}</span><span>{t('credit')}</span><span />
          </div>
          {lines.map((l, i) => (
            <div key={i} className="linea-respuesta">
              <input inputMode="numeric" maxLength={12} placeholder="572" value={l.account_no} aria-label={`${t('account')} ${i + 1}`}
                     onChange={(e) => update(i, 'account_no', e.target.value)} />
              <input inputMode="decimal" placeholder="0,00" value={l.debit} aria-label={`${t('debit')} ${i + 1}`}
                     onChange={(e) => update(i, 'debit', e.target.value)} />
              <input inputMode="decimal" placeholder="0,00" value={l.credit} aria-label={`${t('credit')} ${i + 1}`}
                     onChange={(e) => update(i, 'credit', e.target.value)} />
              <button type="button" className="secundario" disabled={lines.length <= 2} title={t('removeLine')} aria-label={`${t('removeLine')} ${i + 1}`}
                      onClick={() => { setLines(lines.filter((_, k) => k !== i)); setResult(null) }}>✕</button>
            </div>
          ))}
          <div className="linea-respuesta total-respuesta">
            <strong>{t('total')}</strong>
            <span className="num">{m(totals.debit)}</span>
            <span className="num">{m(totals.credit)}</span>
            <span aria-live="polite">{totals.debit || totals.credit ? (totals.balanced ? '✓' : `≠ ${m(Math.abs(totals.debit - totals.credit))}`) : ''}</span>
          </div>
        </div>
        <div className="fila">
          <button type="button" className="secundario" onClick={() => setLines([...lines, emptyLine()])}>+ {t('pr.addLine')}</button>
          <button type="submit" disabled={busy || answerLines(lines).length < 2}>{busy ? `${t('pr.grading')}…` : t('pr.grade')}</button>
        </div>
      </form>
      <ErrorBox error={error} />

      {result && <Correction result={result} m={m} side={side} onRetry={retry} />}

      <div className="fila">
        <button type="button" className="secundario" aria-expanded={showSolution} onClick={() => setShowSolution((s) => !s)}>
          {showSolution ? t('pr.hideSolution') : t('pr.showSolution')}
        </button>
        {next && <Link to={`/practicar/${next.key}`} className="enlace">{t('pr.next')}: {tr(next, 'title')} →</Link>}
      </div>

      {showSolution && (
        <div className="solucion-supuesto">
          <h4>{t('pr.solution')}</h4>
          <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('pr.solution')}>
            <table className="informe">
              <thead><tr><th scope="col">{t('account')}</th><th scope="col" className="num">{t('debit')}</th><th scope="col" className="num">{t('credit')}</th></tr></thead>
              <tbody>
                {x.expected.map((e, i) => (
                  <tr key={i}>
                    <td><span className="codigo">{e.account}</span>{e.alt?.length > 0 && <small> {t('pr.orAlso').replace('{a}', e.alt.join(', '))}</small>}</td>
                    <td className="num">{e.side === 'debit' ? m(e.amount) : ''}</td>
                    <td className="num">{e.side === 'credit' ? m(e.amount) : ''}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="ayuda">{t('pr.groupNote')}</p>
          <p>{tr(x, 'explanation')}</p>
          {op && (
            <p className="donde-registra">
              📍 <Term id="operationCatalog">{t('pr.where')}</Term>: <strong>{tr(op, 'title')}</strong> → {t('pr.screen')} «{screen}»
              <small>{tr(op, 'entry')}</small>
            </p>
          )}
        </div>
      )}
    </div>
  )
}

// Corrección de erp.grade_exercise: cada línea esperada (sin desvelar la cuenta de las que faltan), lo que sobra,
// los errores frecuentes reconocidos y si cuadra
function Correction({ result: r, m, side, onRetry }) {
  const { t, language } = useI18n()
  return (
    <div className={`correccion ${r.ok ? 'bien' : 'mal'}`} role="status">
      <p className="nota-supuesto">
        <strong>{r.ok ? `🎉 ${t('pr.correct')}` : t('pr.notYet')}</strong> · {t('pr.score').replace('{p}', r.score)}
      </p>
      <ul className="comprobaciones">
        {r.lines.map((l, i) => (
          <li key={i} className={l.status === 'ok' ? 'info' : l.status === 'missing' ? 'error' : 'warning'}>
            <span className="icono" aria-hidden="true">{LINE_STATUS[l.status]}</span>{' '}
            {t(`pr.line.${l.status}`).replace('{a}', l.account).replace('{s}', side(l.side)).replace('{m}', m(l.expected))
              .replace('{x}', l.answered == null ? '' : m(l.answered))}
            {l.status === 'ok' && l.alt_used && <small> · {t('pr.altUsed')}</small>}
          </li>
        ))}
        {extraLines(r).map((l, i) => (
          <li key={`x${i}`} className="error">
            <span className="icono" aria-hidden="true">+</span> {t('pr.extra').replace('{a}', l.account).replace('{s}', side(l.side)).replace('{m}', m(l.amount))}
          </li>
        ))}
        {!r.balanced && (
          <li className="error"><span className="icono" aria-hidden="true">≠</span> {t('pr.unbalanced').replace('{d}', m(r.debit)).replace('{c}', m(r.credit))}</li>
        )}
      </ul>
      {r.tips.length > 0 && (
        <div className="bloque-ia learning">
          <h4>💡 {t('pr.tips')}</h4>
          <ul>{r.tips.map((x, i) => <li key={i}>{language === 'en' ? x.msg_en || x.msg : x.msg}</li>)}</ul>
        </div>
      )}
      {!r.ok && <button type="button" className="secundario" onClick={onRetry}>↺ {t('pr.retry')}</button>}
    </div>
  )
}
