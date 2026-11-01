// TABLEROS (v0.52.0 · ADR 0052): funciones puras de la barra superior y de los tableros.
// Las cifras las decide la base de datos (erp.dashboard_data, con el catálogo de 0075); aquí solo se formatean y dibujan.
import { money } from './format'
import { companyPath } from './router'
import { niceTicks } from './chart'

// Dirección de un tablero: #/empresa/<id>/tableros/<código>
export const dashPath = (companyId, code) => companyPath(companyId, `tableros/${code}`)

// Una cifra según su unidad: 184.264,69 € · 7,6 % · 1,32 · 65 días (v0.54.0: los periodos medios, sin decimales)
export function fmtMetric(v, unit, language) {
  if (v == null || Number.isNaN(Number(v))) return '—'
  const n = Number(v)
  const locale = language === 'en' ? 'en-GB' : 'es-ES'
  if (unit === 'eur') return `${money(n, language)} €`
  if (unit === 'days') {
    const d = Math.round(n)
    return `${d.toLocaleString(locale)} ${language === 'en' ? (d === 1 ? 'day' : 'days') : (d === 1 ? 'día' : 'días')}`
  }
  if (unit === 'pct') return `${(n * 100).toLocaleString(locale, { minimumFractionDigits: 1, maximumFractionDigits: 1 })} %`
  return n.toLocaleString(locale, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

// Variación frente al año anterior: diferencia, % sobre el valor absoluto del anterior (null si era 0) y sentido
export function change(value, prev) {
  if (value == null || prev == null) return null
  const diff = Number(value) - Number(prev)
  const base = Math.abs(Number(prev))
  return { diff, pct: base < 0.005 ? null : diff / base, dir: Math.abs(diff) < 0.005 ? 'same' : diff > 0 ? 'up' : 'down' }
}

// Dentro, por debajo o por encima de la zona de referencia (la de los Ratios); null si no hay zona o valor
export function zoneStatus(v, min, max) {
  if (v == null || (min == null && max == null)) return null
  if (min != null && Number(v) < Number(min)) return 'low'
  if (max != null && Number(v) > Number(max)) return 'high'
  return 'ok'
}

// Eje de un gráfico: marcas redondas que incluyen el 0 (las barras y las líneas parten de él)
//   unit 'pct' (v0.53.0): los márgenes llegan como 0,6917; las marcas se redondean en % (0 %, 20 %, 40 %…) y no en
//   unidades, que dejaban todos los márgenes aplastados contra el cero
export function axis(values, unit) {
  const k = unit === 'pct' ? 100 : 1
  const v = values.filter((x) => x != null).map((x) => Number(x) * k)
  const lo = Math.min(0, ...v), hi = Math.max(0, ...v)
  if (hi - lo < 1) return [0, 50, 100].map((x) => x / k)   // todo a cero: un eje limpio, sin «0,5 €»
  return niceTicks(lo, hi).map((x) => x / k)
}

// ¿Hay algo que dibujar este ejercicio? (todo a cero o sin dato → se avisa en vez de enseñar un gráfico vacío)
export const hasData = (widget) => widget.items.some((it) => (it.series ?? []).some((v) => v != null && Math.abs(Number(v)) >= 0.005))

// Filas «mes a mes» de una tarjeta con gráfico (para «Ver como tabla» y el Excel):
//   [{ month, <código>: valor, <código>_prev: valor del año anterior }]
export function seriesRows(data, widget) {
  return (data.months ?? []).map((month, i) => {
    const row = { month }
    for (const it of widget.items) {
      row[it.code] = it.series?.[i] ?? null
      row[`${it.code}_prev`] = it.series_prev?.[i] ?? null
    }
    return row
  })
}

// La tarjeta: su texto en el idioma
export const textOf = (o, field, language) => (language === 'en' ? o?.[`${field}_en`] || o?.[field] : o?.[field]) ?? ''
