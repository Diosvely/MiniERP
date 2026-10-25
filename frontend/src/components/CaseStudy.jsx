import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { money } from '../format'
import { companyPath } from '../router'
import { counts, entryList, entrySection, exportRows, groupCompare, overall, progress, rowLabel } from '../cases'
import { downloadXlsx, fileName } from '../exportXlsx'
import Link from './Link'
import ErrorBox from './ErrorBox'
import Loading from './Loading'
import ReportActions from './ReportActions'

const ICON = { done: '✓', pending: '…', ok: '✓', diff: '✕' }
const CLASS = { done: 'ok', pending: 'warning', ok: 'ok', diff: 'error' }
const SHOW_CODE = ['pyg', 'balance', 'cf_indirect', 'cf_direct']   // el código de la partida, como en su informe

// CASO COMPLETO (v0.46.0): la empresa del caso, operación a operación, y sus cuentas anuales comparadas al céntimo con
// las calculadas a mano. Lo cargó erp.create_case_company (desde la lista de empresas); aquí se estudia:
//   · las 19 operaciones (fecha, asiento, por qué y en qué pantalla), con sus asientos del diario;
//   · en el modo «hasta el cierre», las del cierre las hace quien estudia con el asistente de cierre;
//   · la comparación de las 97 cifras (ok, pendiente del cierre o diferencia), exportable a Excel.
export default function CaseStudy({ company }) {
  const { t, language } = useI18n()
  const en = language === 'en'
  const [kase, setKase] = useState(null)
  const [steps, setSteps] = useState(null)
  const [rows, setRows] = useState(null)
  const [error, setError] = useState('')
  const [reload, setReload] = useState(0)

  useEffect(() => {
    let alive = true
    Promise.all([
      supabase.from('cases').select('*').eq('key', company.case_key),
      supabase.rpc('case_progress', { p_company: company.id }),
      supabase.rpc('case_compare', { p_company: company.id }),
    ]).then(([c, p, x]) => {
      if (!alive) return
      const e = c.error ?? p.error ?? x.error
      if (e) return setError(e.code === 'PGRST202' || e.code === '42P01' ? t('cs.dbMissing') : e.message)
      setError(''); setKase(c.data?.[0] ?? null); setSteps(p.data ?? []); setRows(x.data ?? [])
    })
    return () => { alive = false }
  }, [company.id, company.case_key, reload])   // eslint-disable-line react-hooks/exhaustive-deps

  if (error) return <section className="tarjeta"><ErrorBox error={error} company={company} /></section>
  if (!steps || !rows) return <Loading />

  const year = kase?.year ?? 2026
  const pr = progress(steps)
  const all = counts(rows)
  const groups = groupCompare(rows)
  const m = (v) => money(v, language)
  const to = (section) => companyPath(company.id, section)
  const exportExcel = () => downloadXlsx({
    title: `${t('cs.compareTitle')} · ${company.name ?? ''}`, subtitle: `${t('year')} ${year}`, sheet: t('cs.sheet'),
    file: fileName(t('cs.sheet'), company.name, year),
    columns: [{ header: t('cs.col.group'), key: 'group', type: 'text', width: 28 }, { header: t('cs.col.code'), key: 'code', type: 'text', width: 12 },
      { header: t('cs.col.concept'), key: 'label', type: 'text', width: 60 }, { header: t('cs.col.expected'), key: 'expected', type: 'money' },
      { header: t('cs.col.actual'), key: 'actual', type: 'money' }, { header: t('cs.col.difference'), key: 'difference', type: 'money' },
      { header: t('cs.col.status'), key: 'status', type: 'text', width: 16 }],
    rows: exportRows(rows, t, language, year),
  })

  const step = (s) => {
    const { shown, more } = entryList(s.entries)
    return (
      <li key={s.n} className={`paso-cierre ${s.status}`}>
        <span className={`insignia-estado ${CLASS[s.status]}`} aria-label={t(`cs.stepStatus.${s.status}`)}>{ICON[s.status]}</span>
        <span className="paso-texto">
          <strong>{s.n}. {en ? s.title_en : s.title}</strong>
          <small>{en ? s.date_label_en : s.date_label} · <span className="codigo">{s.entry}</span></small>
          <small>{en ? s.why_en : s.why}</small>
          {shown.length > 0 && (
            <small className="asientos-caso">
              {t('cs.entries')}{' '}
              {shown.map((e, i) => (
                <span key={e.entry_id}>{i > 0 && ', '}<Link to={to(entrySection(e))} className="enlace">{e.year === year ? `nº ${e.entry_no}` : `${e.year} · nº ${e.entry_no}`}</Link></span>))}
              {more > 0 && ` ${t('cs.more').replace('{n}', more)}`}
            </small>)}
        </span>
        <Link to={to(s.screen)} className="enlace">{t(`nav.${s.screen}.label`).replace('{tax}', 'IGIC').replace('{form}', '420')} →</Link>
      </li>
    )
  }

  return (
    <>
      <section className="tarjeta">
        <h2>{kase ? (en ? kase.title_en : kase.title) : t('nav.case.label')}</h2>
        {kase && <p className="ayuda">{en ? kase.description_en : kase.description}</p>}
        <p className="resumen-comprobaciones" role="status">
          <span className="insignia">{t(`cs.mode.${company.case_mode ?? 'full'}`)}</span>
          <span className={`insignia-estado ${pr.done === pr.total ? 'ok' : 'warning'}`}>
            {t('cs.progress').replace('{d}', pr.done).replace('{n}', pr.total)}</span>
          {['ok', 'pending', 'diff'].filter((st) => all[st]).map((st) => (
            <span key={st} className={`insignia-estado ${CLASS[st] ?? 'warning'}`}>{ICON[st]} {t(`cs.count.${st}`).replace('{n}', all[st])}</span>))}
        </p>
        {company.case_mode === 'until_closing' && pr.done < pr.total && (
          <p className="ayuda">{t('cs.untilHelp')} <Link to={to('closing')} className="enlace">{t('nav.closing.label')} →</Link></p>)}
      </section>

      <section className="tarjeta">
        <h3>{t('cs.yearTitle')}</h3>
        <ol className="pasos-cierre">{pr.year.map(step)}</ol>
        <h3>{t('cs.closingTitle')}</h3>
        <ol className="pasos-cierre">{pr.closing.map(step)}</ol>
      </section>

      <section className="tarjeta">
        <div className="titulo-modelo">
          <h3>{t('cs.compareTitle')}</h3>
          <button type="button" className="secundario" onClick={() => setReload((r) => r + 1)}>↻ {t('cs.recompare')}</button>
        </div>
        <p className="ayuda">{t('cs.compareHelp')}</p>
        <ReportActions onExcel={exportExcel} info={`${company.name ?? ''} · ${t('year')} ${year}`} />
        {groups.map((g) => {
          const st = overall(g)
          return (
            <details key={g.kind} className="grupo-caso" open={st === 'diff'}>
              <summary>
                <span className={`insignia-estado ${CLASS[st] ?? 'warning'}`}>{ICON[st]}</span>{' '}
                <strong>{t(`cs.kind.${g.kind}`)}</strong>{' '}
                <span className="ayuda">{t('cs.groupCount').replace('{ok}', g.ok).replace('{n}', g.total)}</span>
              </summary>
              <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t(`cs.kind.${g.kind}`)}>
                <table className="informe">
                  <thead><tr>
                    <th scope="col">{t('cs.col.concept')}</th><th scope="col" className="num">{t('cs.col.expected')}</th>
                    <th scope="col" className="num">{t('cs.col.actual')}</th><th scope="col" className="num">{t('cs.col.difference')}</th>
                    <th scope="col">{t('cs.col.status')}</th>
                  </tr></thead>
                  <tbody>{g.rows.map((r) => (
                    <tr key={r.code}>
                      <td>{SHOW_CODE.includes(r.kind) && <span className="codigo">{r.code}</span>}{rowLabel(r, t, language, year)}</td>
                      <td className="num">{m(r.expected)}</td>
                      <td className="num">{m(r.actual)}</td>
                      <td className="num">{Number(r.difference) === 0 ? '—' : m(r.difference)}</td>
                      <td><span className={`insignia-estado ${CLASS[r.status] ?? 'warning'}`}>{ICON[r.status]} {t(`cs.status.${r.status}`)}</span></td>
                    </tr>))}</tbody>
                </table>
              </div>
              <p><Link to={to(g.screen)} className="enlace">{t('cs.open')} {t(`nav.${g.screen}.label`).replace('{tax}', 'IGIC').replace('{form}', '420')} →</Link></p>
            </details>
          )
        })}
      </section>
    </>
  )
}
