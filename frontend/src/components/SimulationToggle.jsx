import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { companyPath } from '../router'
import { simBanner } from '../reportPeriod'
import Link from './Link'

// SIMULACIÓN CON LOS ASIENTOS EN EDICIÓN (v0.51.0 · ADR 0051): la casilla de los informes y su franja de aviso.
// Marcada, el informe pide a la base de datos p_drafts = true: entran los borradores «en edición» (los que cuadran y
// se podrían contabilizar), nunca los «con error». La franja dice cuántos entran y lleva a «Asientos».

// La casilla (va en la rejilla de filtros del informe) · value · onChange(boolean)
export default function SimulationToggle({ value, onChange }) {
  const { t } = useI18n()
  return (
    <label className="opcion opcion-simulacion" title={t('sim.help')}>
      <input type="checkbox" checked={value} onChange={(e) => onChange(e.target.checked)} /> {t('sim.label')}
    </label>
  )
}

// La franja (debajo de los filtros, solo con la casilla marcada) · year y toDate: el periodo del informe
export function SimulationBanner({ company, year, toDate, value }) {
  const { t } = useI18n()
  const [count, setCount] = useState({ key: '', n: null })
  const key = `${company.id}|${year}|${toDate ?? ''}`

  useEffect(() => {
    if (!value) return
    let alive = true
    supabase.rpc('report_drafts', { p_company: company.id, p_year: Number(year), p_to_date: toDate || null })
      .then(({ data, error }) => { if (alive) setCount({ key, n: error ? null : Number(data ?? 0) }) })
    return () => { alive = false }
  }, [value, key, company.id, year, toDate])

  if (!value) return null
  const n = count.key === key ? count.n : null
  return (
    <p className="franja-simulacion" role="status">
      <strong>{t('sim.prefix')}</strong> · {simBanner(n, t)}{' '}
      <Link to={companyPath(company.id, 'entries')} className="enlace">{t('sim.link')}</Link>
    </p>
  )
}
