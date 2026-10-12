import { useEffect, useRef, useState } from 'react'
import { useI18n } from '../i18n'
import { money } from '../format'
import { niceTicks, waterfall } from '../chart'

// CASCADA DEL EFE: de dónde viene y a dónde va el dinero del año, en un solo vistazo.
//   Efectivo inicial → + Explotación → + Inversión → + Financiación → = Efectivo final
// Las dos barras de saldo, en el color principal; los flujos que suman, en verde y con "+"; los que restan, en rojo y
// con "−": el signo escrito dice lo mismo que el color. Una línea marca el 0 (una empresa puede estar en descubierto).
const H = 250, PAD = { l: 8, r: 8, t: 26, b: 52 }

export default function CashWaterfall({ check, method }) {
  const { t, language } = useI18n()
  const box = useRef(null)
  const [width, setWidth] = useState(640)
  useEffect(() => {
    const el = box.current
    if (!el || typeof ResizeObserver === 'undefined') return
    const ro = new ResizeObserver(([e]) => setWidth(Math.max(280, Math.round(e.contentRect.width))))
    ro.observe(el)
    return () => ro.disconnect()
  }, [])

  const flows = check[method] ?? {}
  const bars = waterfall(check.cash_opening, ['A', 'B', 'C'].map((k) => ({ key: k, value: flows[k] ?? 0 })))
  const ends = bars.flatMap((b) => [b.from, b.to])
  const ticks = niceTicks(Math.min(0, ...ends), Math.max(0, ...ends))
  const lo = ticks[0], hi = ticks[ticks.length - 1]
  const W = width
  const y = (v) => PAD.t + ((hi - v) * (H - PAD.t - PAD.b)) / (hi - lo || 1)
  const slot = (W - PAD.l - PAD.r) / bars.length
  const bw = Math.min(64, slot * 0.6)
  const cx = (i) => PAD.l + slot * i + slot / 2
  const short = W < 520
  const label = (k) => t(`cfw.${k}${short ? 'Short' : ''}`)
  // En el móvil no caben 5 importes completos: miles con un decimal ("−24,6 mil"); el detalle está en la tabla
  const locale = language === 'en' ? 'en-GB' : 'es-ES'
  const amount = (v) => (short && Math.abs(v) >= 1000
    ? `${(Math.abs(v) / 1000).toLocaleString(locale, { maximumFractionDigits: 1 })} ${t('kpi.thousand')}`
    : money(Math.abs(v), language))
  // Signo menos tipográfico (−), también en los saldos negativos (descubierto)
  const signed = (b) => (b.kind === 'total' ? `${b.to < 0 ? '−' : ''}${amount(b.to)}`
    : `${b.kind === 'up' ? '+' : '−'}${amount(b.to - b.from)}`)
  const summary = t('cfw.summary').replace('{a}', money(check.cash_opening, language))
    .replace('{b}', money(check.cash_closing, language))

  return (
    <div className="cascada" ref={box}>
      <svg viewBox={`0 0 ${W} ${H}`} width={W} height={H} role="img" aria-label={summary}>
        <line className="cero" x1={PAD.l} x2={W - PAD.r} y1={y(0)} y2={y(0)} />
        {bars.map((b, i) => {
          const top = y(Math.max(b.from, b.to)), h = Math.max(Math.abs(y(b.from) - y(b.to)), 1.5)
          return (
            <g key={b.key} className={`tramo ${b.kind}`}>
              <rect x={cx(i) - bw / 2} y={top} width={bw} height={h} rx="3" />
              {/* conector punteado hasta la siguiente barra: el nivel del que parte */}
              {i < bars.length - 1 && (
                <line className="conector" x1={cx(i) + bw / 2} x2={cx(i + 1) - bw / 2}
                      y1={y(b.to)} y2={y(b.to)} />
              )}
              <text className="valor" x={cx(i)} y={(b.to >= b.from ? top : top + h + 14) - (b.to >= b.from ? 6 : 0)}
                    textAnchor="middle">{signed(b)}</text>
              <text className="etiqueta" x={cx(i)} y={H - 6} textAnchor="middle">{label(b.key)}</text>
            </g>
          )
        })}
      </svg>
    </div>
  )
}
