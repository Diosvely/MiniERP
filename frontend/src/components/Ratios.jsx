import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { money } from '../format'
import AiAnalyst from './AiAnalyst'
import ErrorBox from './ErrorBox'

// Ratios financieros (Modo auditor): liquidez, solvencia, rentabilidad, actividad y flujos de caja
// Cada ratio con su valoración frente a la zona de referencia, el año anterior y, al pulsarlo,
// la fórmula con los importes reales de la empresa y qué significa.
const GROUPS = ['liquidity', 'solvency', 'profitability', 'activity', 'cash']

export default function Ratios({ company }) {
  const { t, language } = useI18n()
  const [years, setYears] = useState([])
  const [year, setYear] = useState(new Date().getFullYear())
  const [rows, setRows] = useState([])
  const [open, setOpen] = useState({})
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  const locale = language === 'en' ? 'en-GB' : 'es-ES'
  const en = language === 'en'

  useEffect(() => {
    supabase.from('fiscal_years').select('year').eq('company_id', company.id).order('year')
      .then(({ data, error }) => {
        if (error) return setError(error.message)
        setYears(data.map((r) => r.year))
        if (data.length && !data.some((r) => r.year === Number(year))) setYear(data[data.length - 1].year)
      })
  }, [company.id])

  useEffect(() => {
    setLoading(true)
    supabase.rpc('financial_ratios', { p_company: company.id, p_year: Number(year) })
      .then(({ data, error }) => {
        setLoading(false)
        if (error) return setError(error.message)
        setError(''); setRows(data)
      })
  }, [company.id, year])

  const n = (v, d) => Number(v).toLocaleString(locale, { minimumFractionDigits: d, maximumFractionDigits: d })
  // Valor según la unidad: 1,32 · 7,6 % · 71 días · 184.264,69 €
  function fmt(v, unit) {
    if (v == null) return '—'
    if (unit === 'pct') return `${n(v * 100, 1)} %`
    if (unit === 'days') return `${n(v, 0)} ${t('days')}`
    if (unit === 'eur') return money(v, language)
    return n(v, 2)
  }
  function reference(r) {
    const f = (v) => (r.unit === 'eur' ? money(v, language) : fmt(v, r.unit))
    if (r.ref_min != null && r.ref_max != null) return `${f(r.ref_min)} – ${f(r.ref_max)}`
    if (r.ref_min != null) return `≥ ${f(r.ref_min)}`
    if (r.ref_max != null) return `≤ ${f(r.ref_max)}`
    return null
  }
  // De dónde sale: importes reales del numerador y del denominador
  function detail(r) {
    if (r.num == null) return ''
    if (r.den == null) return money(r.num, language)
    if (r.unit === 'days') return `${money(r.num / 365, language)} / ${money(r.den, language)} × 365`
    return `${money(r.num, language)} / ${money(r.den, language)}`
  }
  function trend(r) {
    if (r.value == null || r.value_prev == null || Number(r.value) === Number(r.value_prev)) return ''
    return Number(r.value) > Number(r.value_prev) ? '↑' : '↓'
  }
  const badge = { ok: '✓', low: '▼', high: '▲' }

  return (
    <>
      <section className="tarjeta">
        <h2>{t('ratiosTitle')}</h2>
        <p className="ayuda">{t('ratiosIntro')}</p>
        <div className="rejilla-tres">
          <label>{t('year')}
            <select value={year} onChange={(e) => setYear(e.target.value)}>
              {years.map((y) => <option key={y} value={y}>{y}</option>)}
            </select>
          </label>
        </div>
        <p className="leyenda-ratios">
          <span className="ratio-estado ok">✓ {t('ratioStatus.ok')}</span>
          <span className="ratio-estado low">▼ {t('ratioStatus.low')}</span>
          <span className="ratio-estado high">▲ {t('ratioStatus.high')}</span>
        </p>
        <ErrorBox error={error} company={company} />
        {loading && <p className="ayuda">{t('ratiosLoading')}…</p>}
      </section>

      {GROUPS.map((g) => {
        const list = rows.filter((r) => r.grp === g)
        if (list.length === 0) return null
        return (
          <section key={g} className="tarjeta">
            <h2>{t(`ratioGroup.${g}`)}</h2>
            <p className="ayuda">{t(`ratioGroupHelp.${g}`)}</p>
            <ul className="ratios">
              {list.map((r) => (
                <li key={r.code} className={open[r.code] ? 'abierto' : ''}>
                  <button type="button" className="ratio-fila" aria-expanded={!!open[r.code]}
                          onClick={() => setOpen({ ...open, [r.code]: !open[r.code] })}>
                    <span className="ratio-nombre">
                      <span className="desplegar">{open[r.code] ? '▾' : '▸'}</span> {en ? r.label_en : r.label}
                    </span>
                    <span className="ratio-valor">
                      <strong>{fmt(r.value, r.unit)}</strong>
                      {r.status && <span className={`ratio-estado ${r.status}`} title={t(`ratioStatus.${r.status}`)}>{badge[r.status]}</span>}
                    </span>
                    <span className="ratio-anterior">
                      {Number(year) - 1}: {fmt(r.value_prev, r.unit)} {trend(r)}
                    </span>
                  </button>
                  {open[r.code] && (
                    <div className="ratio-detalle">
                      <p><span className="codigo">{en ? r.formula_en : r.formula}</span></p>
                      {r.num != null && r.den != null && <p>= {detail(r)} = <strong>{fmt(r.value, r.unit)}</strong></p>}
                      {reference(r) && <p className="ayuda">{t('ratioReference')}: {reference(r)}</p>}
                      <p>{en ? r.help_en : r.help}</p>
                    </div>
                  )}
                </li>
              ))}
            </ul>
          </section>
        )
      })}

      {rows.length > 0 && <p className="ayuda">{t('ratiosNote')}</p>}
      {rows.length > 0 && <AiAnalyst company={company} year={year} />}
    </>
  )
}
