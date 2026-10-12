import { useI18n } from '../i18n'

// EVOLUCIÓN DE UN RATIO en todos los ejercicios de la empresa, con su zona de referencia sombreada.
// La tabla ya dice el valor de este año y del anterior; lo que no dice es la TENDENCIA de varios años
// ("la liquidez lleva tres años cayendo y ya está fuera de la zona"). Solo se dibuja al desplegar el ratio.
//   points: [{ year, value }] · ref: { min, max } · fmt: formato del valor (el mismo de la tabla)
const W = 320, H = 110, PAD = { l: 6, r: 6, t: 16, b: 20 }

export default function RatioTrend({ points, refMin, refMax, fmt, label }) {
  const { t } = useI18n()
  const vals = points.map((p) => Number(p.value))
  const lo0 = Math.min(...vals, refMin ?? Infinity), hi0 = Math.max(...vals, refMax ?? -Infinity)
  const pad = (hi0 - lo0 || Math.abs(hi0) || 1) * 0.15
  const lo = lo0 - pad, hi = hi0 + pad
  const x = (i) => PAD.l + 24 + (i * (W - PAD.l - PAD.r - 48)) / Math.max(points.length - 1, 1)
  const y = (v) => PAD.t + ((hi - v) * (H - PAD.t - PAD.b)) / (hi - lo || 1)
  const bandTop = y(refMax ?? hi), bandBottom = y(refMin ?? lo)
  const last = points.length - 1
  const summary = t('ratioTrend.summary').replace('{r}', label)
    .replace('{a}', `${points[0].year} ${fmt(points[0].value)}`).replace('{b}', `${points[last].year} ${fmt(points[last].value)}`)

  return (
    <div className="tendencia-ratio">
      <svg viewBox={`0 0 ${W} ${H}`} role="img" aria-label={summary}>
        {(refMin != null || refMax != null) && (
          <rect className="zona" x={PAD.l} width={W - PAD.l - PAD.r} y={bandTop} height={Math.max(bandBottom - bandTop, 0)} />
        )}
        <polyline className="linea" points={points.map((p, i) => `${x(i)},${y(p.value)}`).join(' ')} />
        {points.map((p, i) => (
          <g key={p.year}>
            <circle className="punto" r={i === last ? 4 : 3} cx={x(i)} cy={y(p.value)} />
            <text className="anio" x={x(i)} y={H - 4} textAnchor="middle">{p.year}</text>
            {(i === 0 || i === last) && (
              <text className="valor" x={x(i)} y={y(p.value) - 8} textAnchor="middle">{fmt(p.value)}</text>
            )}
          </g>
        ))}
      </svg>
      {(refMin != null || refMax != null) && <p className="ayuda">{t('ratioTrend.band')}</p>}
    </div>
  )
}
