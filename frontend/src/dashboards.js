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

// Los periodos de una tarjeta con gráfico: los fines de mes del ejercicio o, con mode 'quarter' (v0.55.0), los cuatro
// trimestres (1, 2, 3, 4)
export const periods = (data, widget) => (widget?.mode === 'quarter' ? [1, 2, 3, 4] : data.months ?? [])

// El nombre de un periodo: el mes («Ene») o el trimestre («1T»; «Q1» en inglés)
export function periodLabel(p, language, monthNames) {
  if (typeof p === 'number') return language === 'en' ? `Q${p}` : `${p}T`
  return monthNames[Number(String(p).slice(5, 7)) - 1]
}

// El impuesto de la empresa, como se dice en cada idioma (VAT → IVA en español; IGIC igual en los dos)
export const taxName = (taxType, language) => (taxType === 'VAT' ? (language === 'en' ? 'VAT' : 'IVA') : taxType ?? '')

// Filas «periodo a periodo» de una tarjeta con gráfico (para «Ver como tabla» y el Excel):
//   [{ period, month (o null), quarter (o null), <código>: valor, <código>_prev: valor del año anterior }]
export function seriesRows(data, widget) {
  const quarter = widget?.mode === 'quarter'
  return periods(data, widget).map((p, i) => {
    const row = { period: p, month: quarter ? null : p, quarter: quarter ? p : null }
    for (const it of widget.items) {
      row[it.code] = it.series?.[i] ?? null
      row[`${it.code}_prev`] = it.series_prev?.[i] ?? null
    }
    return row
  })
}

// La tarjeta: su texto en el idioma
export const textOf = (o, field, language) => (language === 'en' ? o?.[`${field}_en`] || o?.[field] : o?.[field]) ?? ''

// Tabla de una tarjeta (v0.55.0): enlaza a la pantalla de sus métricas (Ratios si alguna es un ratio; si no, la de la
// primera), y la columna «Zona de referencia» sale solo si alguna métrica tiene zona (la del Resumen del año de
// Impuestos no tiene)
export function tableLink(items) {
  return items.some((it) => it.link === 'ratios') ? 'ratios' : items.find((it) => it.link)?.link ?? 'ratios'
}
export const hasZones = (items) => items.some((it) => it.ref_min != null || it.ref_max != null)

// Filas de una tarjeta de ranking (v0.56.0), en el orden en que se enseñan: los N primeros, el «Resto» (si queda
// alguno) y lo que no tiene tercero (si hay importe). share: el % sobre el total del ranking (clientes y proveedores) o
// sobre la cifra de negocios (gastos por naturaleza); null si la base es 0.
//   labels: { rest: (n) => texto, none: texto }
export function rankingRows(r, labels) {
  if (!r) return []
  const base = Number(r.base === 'sales' ? r.sales?.value : r.total?.value)
  const share = (v) => (base && v != null ? Number(v) / base : null)
  const rows = (r.rows ?? []).map((x) => ({ kind: 'row', key: x.key, label: x.label, value: x.value, prev: x.prev, share: share(x.value) }))
  if (Number(r.rest?.count) > 0) {
    rows.push({ kind: 'rest', key: null, label: labels.rest(r.rest.count), value: r.rest.value, prev: r.rest.prev, share: share(r.rest.value) })
  }
  if (Math.abs(Number(r.none?.value ?? 0)) >= 0.005 || Math.abs(Number(r.none?.prev ?? 0)) >= 0.005) {
    rows.push({ kind: 'none', key: null, label: labels.none, value: r.none.value, prev: r.none.prev, share: share(r.none.value) })
  }
  return rows
}

