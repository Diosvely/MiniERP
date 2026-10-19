import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { money } from '../format'
import { workQuarter, workYear } from '../workDate'
import { companyPath } from '../router'
import { FORM_SOURCES } from '../sources'
import { downloadXlsx, fileName } from '../exportXlsx'
import { formResult, group349, groupBoxes, totals347 } from '../taxForms'
import Link from './Link'
import Empty from './Empty'
import Sources from './Sources'
import ReportActions from './ReportActions'
import ErrorBox from './ErrorBox'

// MODELOS (v0.39.0): el borrador de cada modelo con sus casillas oficiales, calculado por la base de datos desde el libro
// registro de facturas (0051 y 0052), como el borrador de A3 / Sage o el «VAT statement» de Business Central:
//   · trimestral: 303 (IVA) o 420 (IGIC) · anual: 390 o 425 · 347 (operaciones con terceros) · 349 (intracomunitarias, IVA)
// Cada modelo enseña sus fuentes oficiales (📘). El ERP no presenta nada: el borrador se copia en la sede electrónica.
export default function TaxForms({ company }) {
  const { t, language } = useI18n()
  const igic = company.tax_territory === 'canary_islands'
  const forms = igic ? { quarter: '420', annual: '425' } : { quarter: '303', annual: '390' }
  const tabs = igic ? ['quarter', 'annual', '347'] : ['quarter', 'annual', '347', '349']
  const [tab, setTab] = useState('quarter')
  const [years, setYears] = useState([])
  const [year, setYear] = useState(() => workYear(company))
  const [quarter, setQuarter] = useState(() => workQuarter(company))
  const [rows, setRows] = useState(null)
  const [period349, setPeriod349] = useState(null)
  const [error, setError] = useState('')
  const m = (v) => money(v, language)
  const pct = (v) => `${Number(v).toLocaleString(language === 'en' ? 'en-GB' : 'es-ES', { maximumFractionDigits: 2 })} %`
  const form = tab === 'quarter' ? forms.quarter : tab === 'annual' ? forms.annual : tab

  useEffect(() => {
    supabase.from('fiscal_years').select('year').eq('company_id', company.id).order('year')
      .then(({ data, error }) => {
        if (error) return setError(error.message)
        setYears((data ?? []).map((r) => r.year))
      })
  }, [company.id])

  useEffect(() => {
    let alive = true
    const y = Number(year), q = Number(quarter)
    const call = tab === 'quarter' ? supabase.rpc('tax_form_boxes', { p_company: company.id, p_year: y, p_quarter: q })
      : tab === 'annual' ? supabase.rpc('tax_form_boxes', { p_company: company.id, p_year: y, p_quarter: null })
        : tab === '347' ? supabase.rpc('form_347', { p_company: company.id, p_year: y })
          : supabase.rpc('form_349', { p_company: company.id, p_year: y, p_quarter: q })
    Promise.all([call, tab === '349' ? supabase.rpc('form_349_period', { p_company: company.id, p_year: y, p_quarter: q }) : null])
      .then(([r, p]) => {
        if (!alive) return
        if (r.error) { setRows([]); return setError(r.error.code === 'PGRST202' ? t('tf.dbMissing') : r.error.message) }
        setError(''); setRows(r.data ?? []); setPeriod349(p?.data ?? null)
      })
    return () => { alive = false }
  }, [company.id, tab, year, quarter])   // eslint-disable-line react-hooks/exhaustive-deps

  const value = (r) => (r.kind === 'rate' || r.kind === 'pct' ? pct(r.amount) : m(r.amount))
  const concept = (r) => (language === 'en' ? r.concept_en || r.concept : r.concept)
  const period = tab === 'annual' || tab === '347' ? String(year) : `${quarter}T ${year}`
  const title = `${t('tf.form')} ${form} · ${t(`tf.formName.${form}`)}`

  function excelBoxes() {
    return downloadXlsx({
      title: `${title} · ${company.name}`, subtitle: period, sheet: form, file: fileName(t('tf.form'), form, company.name, period),
      columns: [{ header: t('tf.col.section'), key: 'section', type: 'text', width: 14 }, { header: t('tf.col.box'), key: 'box', type: 'text', width: 8 },
        { header: t('tf.col.concept'), key: 'concept', type: 'text', width: 60 }, { header: t('tf.col.amount'), key: 'amount', type: 'money' }],
      rows: (rows ?? []).map((r) => ({ ...r, section: t(`tf.section.${r.section}`), concept: concept(r) })),
    })
  }
  function excel347() {
    return downloadXlsx({
      title: `${title} · ${company.name}`, subtitle: period, sheet: '347', file: fileName(t('tf.form'), '347', company.name, period),
      columns: [{ header: t('tf.col.key'), key: 'op_key', type: 'text', width: 6 }, { header: t('tf.col.partner'), key: 'partner_name', type: 'text', width: 34 },
        { header: t('tf.col.vat'), key: 'vat_registration_no', type: 'text', width: 14 },
        ...['q1', 'q2', 'q3', 'q4'].map((k, i) => ({ header: `${i + 1}T`, key: k, type: 'money' })), { header: t('tf.col.total'), key: 'total', type: 'money' }],
      rows: rows ?? [],
    })
  }

  const result = (tab === 'quarter' || tab === 'annual') && rows ? formResult(form, rows) : null
  const t347 = tab === '347' && rows ? totals347(rows) : null
  const g349 = tab === '349' && rows ? group349(rows) : null

  return (
    <>
      <section className="tarjeta modelos">
        <h2>{t('tf.title')}</h2>
        <p className="ayuda">{t('tf.intro')}</p>
        <div className="pestanas" role="group" aria-label={t('tf.title')}>
          {tabs.map((x) => (
            <button key={x} type="button" className={tab === x ? 'activa' : ''} aria-pressed={tab === x} onClick={() => setTab(x)}>
              {x === 'quarter' ? forms.quarter : x === 'annual' ? forms.annual : x}
              <small>{t(`tf.tab.${x}`)}</small>
            </button>
          ))}
        </div>
        <div className="rejilla-tres">
          <label>{t('year')}
            <select value={year} onChange={(e) => setYear(e.target.value)}>
              {(years.length ? years : [year]).map((y) => <option key={y} value={y}>{y}</option>)}
            </select>
          </label>
          {(tab === 'quarter' || tab === '349') && (
            <label>{t('quarter')}
              <select value={quarter} onChange={(e) => setQuarter(e.target.value)}>
                {[1, 2, 3, 4].map((q) => <option key={q} value={q}>{q}T</option>)}
              </select>
            </label>
          )}
        </div>
        <ErrorBox error={error} company={company} />
      </section>

      <section className="tarjeta">
        <div className="titulo-modelo"><h2>{title} · {period}</h2><Sources ids={FORM_SOURCES[form]} /></div>
        <p className="ayuda">{t(`tf.help.${form}`)}</p>
        {rows === null ? null : (tab === 'quarter' || tab === 'annual') ? (
          <>
            {result && (
              <p className={`resultado-modelo ${result.outcome}`} role="status">
                {t(`tf.result.${result.outcome}`).replace('{b}', result.box).replace('{m}', m(Math.abs(result.amount)))}
              </p>
            )}
            {tab === 'quarter' && <p className="ayuda">{t('tf.settlementNote')} <Link to={companyPath(company.id, 'settlement')} className="enlace">{t('tf.goSettlement')} →</Link></p>}
            <ReportActions info={`${company.name} · ${title} · ${period}`} onExcel={excelBoxes} />
            {groupBoxes(rows).map((g) => (
              <div key={g.section} className="tabla-ancha" tabIndex={0} role="region" aria-label={t(`tf.section.${g.section}`)}>
                <table className="casillas">
                  <caption>{t(`tf.section.${g.section}`)}</caption>
                  <thead><tr><th scope="col">{t('tf.col.box')}</th><th scope="col">{t('tf.col.concept')}</th><th scope="col" className="num">{t('tf.col.amount')}</th></tr></thead>
                  <tbody>{g.rows.map((r, i) => (
                    <tr key={`${r.box}-${i}`} className={r.kind === 'amount' ? 'total' : ''}>
                      <td className="casilla">{r.box}</td><td>{concept(r)}</td><td className="num">{value(r)}</td>
                    </tr>))}</tbody>
                </table>
              </div>
            ))}
          </>
        ) : tab === '347' ? (
          rows.length === 0 ? <Empty icon="✅" text={t('tf.empty347')} help={t('tf.empty347Help')} /> : (
            <>
              <dl className="cifras-comprobacion">
                <div><dt>{t('tf.sales347')}</dt><dd>{m(t347.sales)}</dd></div>
                <div><dt>{t('tf.purchases347')}</dt><dd>{m(t347.purchases)}</dd></div>
                <div><dt>{t('tf.partners347')}</dt><dd>{t347.count}</dd></div>
              </dl>
              {t347.missing > 0 && <p className="aviso">⚠ {t('tf.missingVat').replace('{n}', t347.missing)}</p>}
              <ReportActions info={`${company.name} · ${title} · ${period}`} onExcel={excel347} />
              <div className="tabla-ancha" tabIndex={0} role="region" aria-label={title}>
                <table className="casillas">
                  <thead><tr>
                    <th scope="col">{t('tf.col.key')}</th><th scope="col">{t('tf.col.partner')}</th><th scope="col">{t('tf.col.vat')}</th>
                    {[1, 2, 3, 4].map((q) => <th key={q} scope="col" className="num">{q}T</th>)}<th scope="col" className="num">{t('tf.col.total')}</th>
                  </tr></thead>
                  <tbody>{rows.map((r) => (
                    <tr key={`${r.op_key}-${r.partner_id}`}>
                      <td className="casilla">{r.op_key}</td><td>{r.partner_name}</td>
                      <td>{r.missing_vat_no ? <span className="vencida">⚠ {t('tf.noVat')}</span> : r.vat_registration_no}</td>
                      <td className="num">{m(r.q1)}</td><td className="num">{m(r.q2)}</td><td className="num">{m(r.q3)}</td><td className="num">{m(r.q4)}</td>
                      <td className="num"><strong>{m(r.total)}</strong></td>
                    </tr>))}</tbody>
                </table>
              </div>
              <p className="ayuda">{t('tf.keys347')}</p>
            </>
          )
        ) : (
          <>
            {period349 && <p className={`aviso-periodo ${period349}`}>{t(`tf.period.${period349}`)}</p>}
            {rows.length === 0 ? <Empty icon="✅" text={t('tf.empty349')} /> : (
              <div className="tabla-ancha" tabIndex={0} role="region" aria-label={title}>
                <table className="casillas">
                  <thead><tr>
                    <th scope="col">{t('tf.col.key')}</th><th scope="col">{t('tf.col.partner')}</th><th scope="col">{t('tf.col.vatEu')}</th>
                    <th scope="col">{t('tf.col.corrected')}</th><th scope="col" className="num">{t('tf.col.amount')}</th><th scope="col" className="num">{t('tf.col.previous')}</th>
                  </tr></thead>
                  <tbody>
                    {[...g349.operations, ...g349.rectifications].map((r, i) => (
                      <tr key={`${r.section}-${r.partner_id}-${r.op_key}-${i}`}>
                        <td className="casilla" title={t(`tf.key349.${r.op_key}`)}>{r.op_key}</td><td>{r.partner_name}</td><td>{r.vat_registration_no}</td>
                        <td>{r.section === 'rectification' ? `${t('tf.rectification')} · ${r.corrected_period}` : '—'}</td>
                        <td className="num">{m(r.amount)}</td><td className="num">{r.previously_declared == null ? '' : m(r.previously_declared)}</td>
                      </tr>))}
                  </tbody>
                </table>
              </div>
            )}
            <p className="ayuda">{t('tf.keys349')}</p>
          </>
        )}
      </section>
    </>
  )
}
