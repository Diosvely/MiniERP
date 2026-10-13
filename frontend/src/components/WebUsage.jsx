import { useEffect, useRef, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { niceTicks, barPath } from '../chart'

// USO DE LA WEB (solo el propietario, v0.31.0): cuánta gente prueba la demo, cuántos se registran y si vuelven.
// Los datos los da erp.web_usage (0034): cifras agregadas, sin correos, sin contar al propietario.
// Menos es más: 4 cifras y UN gráfico (visitantes de la demo por día), con los registros del día en el tooltip
// y en la tabla. Barras porque son recuentos de días sueltos, no una magnitud continua.
const H = 170
const PAD = { l: 30, r: 8, t: 10, b: 24 }

export default function WebUsage() {
  const { t, language } = useI18n()
  const [u, setU] = useState(null)
  const [error, setError] = useState('')
  const [table, setTable] = useState(false)
  const [hover, setHover] = useState(null)
  const [width, setWidth] = useState(640)
  const box = useRef(null)

  useEffect(() => {
    supabase.rpc('web_usage', { p_days: 30 }).then(({ data, error }) => {
      if (error) setError(error.code === 'PGRST202' ? 'db_missing' : error.message)
      else setU(data)
    })
  }, [])   // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    const el = box.current
    if (!el || typeof ResizeObserver === 'undefined') return
    const ro = new ResizeObserver(([e]) => setWidth(Math.max(280, Math.round(e.contentRect.width))))
    ro.observe(el)
    return () => ro.disconnect()
  }, [u, table])

  if (error) return <section className="tarjeta"><h2>{t('usage.title')}</h2><p className="aviso">⚠ {error === 'db_missing' ? t('usage.dbMissing') : error}</p></section>
  if (!u) return null

  const locale = language === 'en' ? 'en-GB' : 'es-ES'
  const n = (v) => Number(v ?? 0).toLocaleString(locale)
  const dayLabel = (d, long) => new Date(`${d}T00:00:00`).toLocaleDateString(locale, long
    ? { weekday: 'short', day: 'numeric', month: 'short' } : { day: 'numeric', month: 'short' }).replace('.', '')
  const series = u.series ?? []
  const values = series.map((d) => Number(d.guests))
  const max = Math.max(0, ...values)
  const ticks = niceTicks(0, Math.max(max, 2))
  const top = ticks[ticks.length - 1]
  const W = width
  const slot = (W - PAD.l - PAD.r) / Math.max(series.length, 1)
  const bw = Math.max(slot - 2, 2)                                  // 2 px de separación entre barras
  const x = (i) => PAD.l + i * slot + 1
  const y = (v) => PAD.t + ((top - v) * (H - PAD.t - PAD.b)) / (top || 1)
  const maxAt = values.indexOf(max)
  const summary = t('usage.chartSummary').replace('{n}', n(u.guests_period)).replace('{d}', u.days)
    .replace('{m}', n(max)).replace('{day}', max > 0 ? dayLabel(series[maxAt].day) : '—')

  const tiles = [
    { key: 'guests', value: u.guests_period, detail: t('usage.guestsDetail').replace('{a}', n(u.guests_today)).replace('{b}', n(u.guests_7d)) },
    { key: 'signups', value: u.signups_period, detail: t('usage.signupsDetail').replace('{a}', n(u.signups_7d)).replace('{b}', n(u.users_total)) },
    { key: 'active', value: u.active_7d, detail: t('usage.activeDetail').replace('{b}', n(u.users_total)) },
    { key: 'companies', value: u.companies_period, detail: t('usage.companiesDetail').replace('{a}', n(u.imports_period)).replace('{b}', n(u.ai_calls_period)) },
  ]

  return (
    <section className="tarjeta uso-web">
      <div className="grafico-cabecera">
        <h2>{t('usage.title')}</h2>
        <button type="button" className="enlace" aria-pressed={table} onClick={() => setTable(!table)}>
          {table ? t('kpi.chartShow') : t('kpi.chartTable')}
        </button>
      </div>
      <p className="ayuda">{t('usage.intro').replace('{d}', u.days)}</p>

      <ul className="uso-kpis">
        {tiles.map((k) => (
          <li key={k.key} className="kpi">
            <span className="kpi-titulo">{t(`usage.${k.key}`)}</span>
            <span className="kpi-valor">{n(k.value)}</span>
            <span className="kpi-detalle">{k.detail}</span>
          </li>
        ))}
      </ul>

      <h3>{t('usage.chartTitle').replace('{d}', u.days)}</h3>
      {table ? (
        <div className="tabla-ancha" tabIndex={0}>
          <table className="informe">
            <thead><tr><th>{t('usage.day')}</th><th className="num">{t('usage.guests')}</th><th className="num">{t('usage.signups')}</th></tr></thead>
            <tbody>
              {[...series].reverse().map((d) => (
                <tr key={d.day}><td>{dayLabel(d.day, true)}</td><td className="num">{n(d.guests)}</td><td className="num">{n(d.signups)}</td></tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : max === 0 ? (
        <p className="ayuda">{t('usage.noVisits')}</p>
      ) : (
        <div className="grafico" ref={box}>
          <svg viewBox={`0 0 ${W} ${H}`} width={W} height={H} role="img" aria-label={summary} onMouseLeave={() => setHover(null)}>
            <g className="rejilla">
              {ticks.map((v) => <line key={v} x1={PAD.l} x2={W - PAD.r} y1={y(v)} y2={y(v)} />)}
            </g>
            <g className="eje">
              {ticks.map((v) => <text key={v} x={PAD.l - 6} y={y(v) + 4} textAnchor="end">{n(v)}</text>)}
              {series.map((d, i) => (i % 7 === (series.length - 1) % 7) && (
                <text key={d.day} x={x(i) + bw / 2} y={H - 6} textAnchor="middle">{dayLabel(d.day)}</text>
              ))}
            </g>
            {series.map((d, i) => (
              <g key={d.day}>
                {values[i] > 0 && <path className={hover === i ? 'barra activa' : 'barra'} d={barPath(x(i), y(values[i]), bw, y(0) - y(values[i]), 4)} />}
                {/* Zona de ratón más grande que la barra: toda la columna */}
                <rect x={PAD.l + i * slot} y={PAD.t} width={slot} height={H - PAD.t - PAD.b} fill="transparent"
                      onMouseEnter={() => setHover(i)} />
              </g>
            ))}
          </svg>
          {hover !== null && (
            <div className="tooltip" style={{ left: Math.min(x(hover) + bw + 6, W - 190), top: Math.max(y(values[hover]) - 46, 0) }}>
              {dayLabel(series[hover].day, true)}<br />
              {t('usage.guests')}: <strong>{n(series[hover].guests)}</strong> · {t('usage.signups')}: <strong>{n(series[hover].signups)}</strong>
            </div>
          )}
        </div>
      )}
      <p className="ayuda">{t('usage.help')}</p>
    </section>
  )
}
