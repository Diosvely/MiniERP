import { useEffect, useRef, useState } from 'react'
import { useI18n } from '../i18n'
import { money } from '../format'
import { niceTicks } from '../chart'

// TESORERÍA A FIN DE MES: un solo gráfico, porque es la pregunta que se hace primero cualquiera que lleva una empresa
// ("¿cuánto dinero tengo y hacia dónde va?"). Menos es más:
//   · una línea (2 px) con un área muy suave debajo, rejilla discreta y solo 3 marcas en el eje
//   · el último saldo escrito al final de la línea (lo único que se rotula)
//   · al pasar el ratón: el mes y su importe
//   · "Ver como tabla" para quien no pueda o no quiera leer el gráfico
// Dibujado a mano en SVG: unas pocas líneas, sin librerías y sin tocar la CSP.
const H_WIDE = 220, H_NARROW = 200
const PAD = { l: 52, r: 12, t: 14, b: 26 }

export default function CashChart({ months, year }) {
  const { t, language } = useI18n()
  const box = useRef(null)
  const [width, setWidth] = useState(640)
  const [hover, setHover] = useState(null)
  const [table, setTable] = useState(false)

  useEffect(() => {
    const el = box.current
    if (!el || typeof ResizeObserver === 'undefined') return
    const ro = new ResizeObserver(([e]) => setWidth(Math.max(280, Math.round(e.contentRect.width))))
    ro.observe(el)
    return () => ro.disconnect()
  }, [])

  const locale = language === 'en' ? 'en-GB' : 'es-ES'
  const eur = (v) => `${money(v, language)} €`
  const monthName = (m) => new Date(`${m}T00:00:00`).toLocaleDateString(locale, { month: 'short' }).replace('.', '')
  const values = months.map((m) => Number(m.balance))
  const ticks = niceTicks(Math.min(0, ...values), Math.max(...values))
  const lo = ticks[0], hi = ticks[ticks.length - 1]
  const W = width, H = W < 500 ? H_NARROW : H_WIDE
  const x = (i) => PAD.l + (i * (W - PAD.l - PAD.r)) / Math.max(months.length - 1, 1)
  const y = (v) => PAD.t + ((hi - v) * (H - PAD.t - PAD.b)) / (hi - lo || 1)
  const pts = values.map((v, i) => `${x(i)},${y(v)}`).join(' ')
  const last = values.length - 1
  const short = (v) => (Math.abs(hi) >= 10000 ? `${(v / 1000).toLocaleString(locale)} ${t('kpi.thousand')}` : v.toLocaleString(locale))
  const every = W < 500 && months.length > 6 ? 2 : 1   // en el móvil, un mes sí y otro no
  const first = values[0], max = Math.max(...values), maxAt = values.indexOf(max)
  const summary = t('kpi.chartSummary')
    .replace('{a}', `${monthName(months[0].month)} ${eur(first)}`)
    .replace('{b}', `${monthName(months[last].month)} ${eur(values[last])}`)
    .replace('{m}', `${eur(max)} (${monthName(months[maxAt].month)})`)

  function onMove(e) {
    const r = e.currentTarget.getBoundingClientRect()
    const px = ((e.clientX - r.left) * W) / r.width
    const i = Math.round(((px - PAD.l) * Math.max(months.length - 1, 1)) / (W - PAD.l - PAD.r))
    setHover(Math.max(0, Math.min(last, i)))
  }

  return (
    <section className="tarjeta grafico-tesoreria">
      <div className="grafico-cabecera">
        <h2>{t('kpi.chartTitle').replace('{y}', year)}</h2>
        <button type="button" className="enlace" aria-pressed={table} onClick={() => setTable(!table)}>
          {table ? t('kpi.chartShow') : t('kpi.chartTable')}
        </button>
      </div>

      {table ? (
        <table className="informe">
          <thead><tr><th>{t('kpi.month')}</th><th className="num">{t('kpi.cash')}</th></tr></thead>
          <tbody>
            {months.map((m) => (
              <tr key={m.month}>
                <td>{new Date(`${m.month}T00:00:00`).toLocaleDateString(locale, { month: 'long', year: 'numeric' })}</td>
                <td className="num">{eur(m.balance)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : (
        <div className="grafico" ref={box}>
          <svg viewBox={`0 0 ${W} ${H}`} width={W} height={H} role="img" aria-label={summary}>
            <g className="rejilla">
              {ticks.map((v) => <line key={v} x1={PAD.l} x2={W - PAD.r} y1={y(v)} y2={y(v)} />)}
            </g>
            <g className="eje">
              {ticks.filter((_, i) => i % 2 === 0 || ticks.length <= 3).map((v) => (
                <text key={v} x={PAD.l - 8} y={y(v) + 4} textAnchor="end">{short(v)}</text>
              ))}
              {months.map((m, i) => (i % every === 0 || i === last) && (
                <text key={m.month} x={x(i)} y={H - 6} textAnchor="middle">{monthName(m.month)}</text>
              ))}
            </g>
            <polygon className="area" points={`${x(0)},${y(Math.max(lo, 0))} ${pts} ${x(last)},${y(Math.max(lo, 0))}`} />
            <polyline className="linea" points={pts} />
            {hover !== null && <line className="cruz" x1={x(hover)} x2={x(hover)} y1={PAD.t} y2={H - PAD.b} />}
            <circle className="punto" r="5" cx={x(hover ?? last)} cy={y(values[hover ?? last])} />
            {hover === null && (
              // Si la línea llega bajando, el rótulo va debajo del punto; si llega subiendo, encima: así no la tapa
              <text className="valor-final" x={x(last) - 8} y={y(values[last]) + (values[last - 1] > values[last] ? 20 : -10)}
                    textAnchor="end">{eur(values[last])}</text>
            )}
            <rect x={PAD.l} y={PAD.t} width={W - PAD.l - PAD.r} height={H - PAD.t - PAD.b} fill="transparent"
                  onMouseMove={onMove} onMouseLeave={() => setHover(null)} />
          </svg>
          {hover !== null && (
            <div className="tooltip" style={{ left: Math.min(x(hover) + 10, W - 180), top: Math.max(y(values[hover]) - 42, 0) }}>
              {new Date(`${months[hover].month}T00:00:00`).toLocaleDateString(locale, { month: 'short', year: 'numeric' })}
              {' · '}<strong>{eur(values[hover])}</strong>
            </div>
          )}
        </div>
      )}
      <p className="ayuda">{t('kpi.chartHelp')}</p>
    </section>
  )
}
