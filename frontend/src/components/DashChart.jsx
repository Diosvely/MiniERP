import { useEffect, useRef, useState } from 'react'
import { useI18n } from '../i18n'
import { axis, fmtMetric, hasData, seriesRows, textOf } from '../dashboards'
import { monthNames } from '../reportPeriod'

// GRÁFICO DE UNA TARJETA DE TABLERO (v0.52.0): barras (lo de cada mes) o líneas (a fin de mes, frente al año anterior).
// Dibujado a mano en SVG como los de Inicio: sin librerías ni cambios en la CSP. Cada serie lleva su nombre en la
// leyenda (nunca solo color) y «Ver como tabla» enseña los números con el año anterior.
//   data: la respuesta de erp.dashboard_data · widget: la tarjeta (kind 'bars' | 'lines')
const PAD = { l: 56, r: 12, t: 12, b: 26 }

export default function DashChart({ data, widget }) {
  const { t, language } = useI18n()
  const box = useRef(null)
  const [width, setWidth] = useState(640)
  const [table, setTable] = useState(false)
  const [hover, setHover] = useState(null)

  useEffect(() => {
    const el = box.current
    if (!el || typeof ResizeObserver === 'undefined') return
    const ro = new ResizeObserver(([e]) => setWidth(Math.max(260, Math.round(e.contentRect.width))))
    ro.observe(el)
    return () => ro.disconnect()
  }, [table])

  const locale = language === 'en' ? 'en-GB' : 'es-ES'
  const names = monthNames(language)
  const months = data.months ?? []
  const mName = (d) => names[Number(String(d).slice(5, 7)) - 1]
  const lines = widget.kind === 'lines'
  const withPrev = lines && data.has_prev
  const items = widget.items
  const unit = items[0]?.unit
  const all = items.flatMap((it) => [...(it.series ?? []), ...(withPrev ? it.series_prev ?? [] : [])])
  const ticks = axis(all)
  const lo = ticks[0], hi = ticks[ticks.length - 1]
  const W = width, H = W < 500 ? 200 : 230
  const n = Math.max(months.length, 1)
  const slot = (W - PAD.l - PAD.r) / n
  const cx = (i) => PAD.l + slot * (i + 0.5)
  const y = (v) => PAD.t + ((hi - Number(v)) * (H - PAD.t - PAD.b)) / (hi - lo || 1)
  const short = (v) => (Math.abs(hi) >= 10000 || Math.abs(lo) >= 10000
    ? `${(v / 1000).toLocaleString(locale)} ${t('kpi.thousand')}` : Number(v).toLocaleString(locale))
  const every = W < 500 && n > 6 ? 2 : 1
  const year = data.year, prevYear = Number(data.year) - 1
  const label = (it) => textOf(it, 'label', language)
  const rows = seriesRows(data, widget)
  // Resumen para el lector de pantalla: el último mes con dato de cada serie
  const lastIdx = Math.max(-1, ...items.map((it) => (it.series ?? []).findLastIndex((v) => v != null)))
  const summary = `${textOf(widget, 'label', language)} ${year}: ` + items.map((it) =>
    `${label(it)} ${lastIdx >= 0 ? `${mName(months[lastIdx])} ${fmtMetric(it.series[lastIdx], it.unit, language)}` : '—'}`).join(' · ')

  // Una polilínea por tramos (un mes sin dato la corta)
  const path = (vals) => vals.map((v, i) => (v == null ? null : `${cx(i)},${y(v)}`)).filter(Boolean).join(' ')
  const barW = Math.max(3, Math.min(22, (slot * 0.7) / Math.max(items.length, 1)))

  function onMove(e) {
    const r = e.currentTarget.getBoundingClientRect()
    const px = ((e.clientX - r.left) * W) / r.width
    setHover(Math.max(0, Math.min(n - 1, Math.floor((px - PAD.l) / slot))))
  }

  return (
    <>
      <div className="grafico-cabecera">
        <h3>{textOf(widget, 'label', language)}</h3>
        <button type="button" className="enlace" aria-pressed={table} onClick={() => setTable(!table)}>
          {table ? t('kpi.chartShow') : t('kpi.chartTable')}
        </button>
      </div>
      {table ? (
        <div className="tabla-ancha" tabIndex={0} role="region" aria-label={textOf(widget, 'label', language)}>
          <table className="informe">
            <thead>
              <tr>
                <th>{t('kpi.month')}</th>
                {items.map((it) => <th key={it.code} className="num">{label(it)} {year}</th>)}
                {data.has_prev && items.map((it) => <th key={`${it.code}p`} className="num">{label(it)} {prevYear}</th>)}
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.month}>
                  <td>{names[Number(r.month.slice(5, 7)) - 1]}</td>
                  {items.map((it) => <td key={it.code} className="num">{fmtMetric(r[it.code], it.unit, language)}</td>)}
                  {data.has_prev && items.map((it) => <td key={`${it.code}p`} className="num anterior">
                    {fmtMetric(r[`${it.code}_prev`], it.unit, language)}</td>)}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : (
        <div className="grafico" ref={box}>
          <svg viewBox={`0 0 ${W} ${H}`} width={W} height={H} role="img" aria-label={summary}>
            <g className="rejilla">{ticks.map((v) => <line key={v} x1={PAD.l} x2={W - PAD.r} y1={y(v)} y2={y(v)} />)}</g>
            <line className="cero" x1={PAD.l} x2={W - PAD.r} y1={y(0)} y2={y(0)} />
            <g className="eje">
              {ticks.map((v) => <text key={v} x={PAD.l - 8} y={y(v) + 4} textAnchor="end">{short(v)}</text>)}
              {months.map((m, i) => (i % every === 0) && <text key={m} x={cx(i)} y={H - 6} textAnchor="middle">{mName(m)}</text>)}
            </g>
            {lines ? items.map((it, k) => (
              <g key={it.code}>
                {withPrev && <polyline className={`serie-linea anterior serie-${k}`} points={path(it.series_prev ?? [])} />}
                <polyline className={`serie-linea serie-${k}`} points={path(it.series ?? [])} />
                {(it.series ?? []).map((v, i) => v != null && (i === lastIdx || i === hover) && (
                  <circle key={i} className={`serie-punto serie-${k}`} r="4" cx={cx(i)} cy={y(v)} />))}
              </g>
            )) : items.map((it, k) => (it.series ?? []).map((v, i) => v != null && (
              <rect key={`${it.code}${i}`} className={`serie-barra serie-${k}${hover === i ? ' activa' : ''}`}
                    x={cx(i) - (barW * items.length) / 2 + k * barW} width={barW - 1}
                    y={Math.min(y(v), y(0))} height={Math.max(1, Math.abs(y(v) - y(0)))} />
            )))}
            {hover !== null && lines && <line className="cruz" x1={cx(hover)} x2={cx(hover)} y1={PAD.t} y2={H - PAD.b} />}
            <rect x={PAD.l} y={PAD.t} width={W - PAD.l - PAD.r} height={H - PAD.t - PAD.b} fill="transparent"
                  onMouseMove={onMove} onMouseLeave={() => setHover(null)} />
          </svg>
          {hover !== null && (
            <div className="tooltip" style={{ left: Math.min(cx(hover) + 10, W - 200), top: 4 }}>
              <strong>{mName(months[hover])}</strong>
              {items.map((it) => (
                <span key={it.code}> · {label(it)} {fmtMetric(it.series?.[hover], unit, language)}
                  {withPrev && <> ({prevYear}: {fmtMetric(it.series_prev?.[hover], unit, language)})</>}</span>
              ))}
            </div>
          )}
        </div>
      )}
      <p className="leyenda-grafico">
        {items.map((it, k) => <span key={it.code}><i className={`muestra serie-${k}`} aria-hidden="true" /> {label(it)} {year}</span>)}
        {withPrev && items.map((it, k) => <span key={`${it.code}p`}><i className={`muestra anterior serie-${k}`} aria-hidden="true" /> {label(it)} {prevYear}</span>)}
      </p>
      {!hasData(widget) && <p className="ayuda" role="note">{t('dash.empty').replace('{y}', year)}</p>}
      {textOf(widget, 'help', language) && <p className="ayuda">{textOf(widget, 'help', language)}</p>}
    </>
  )
}
