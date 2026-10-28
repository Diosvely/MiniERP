// MES RÁPIDO Y SIMULACIÓN EN LOS INFORMES (v0.51.0 · ADR 0051)
// Funciones puras: las usan Balance, PyG, Sumas y saldos, Mayor, Comprobaciones, Flujos y Ratios.

const pad = (n) => String(n).padStart(2, '0')

// Días del mes m (1–12) del año y
export const daysIn = (y, m) => new Date(Date.UTC(Number(y), Number(m), 0)).getUTCDate()

// Último día del mes m del año y → 'aaaa-mm-dd' (el «hasta» de un botón de mes)
export const monthEnd = (y, m) => `${y}-${pad(m)}-${pad(daysIn(y, m))}`

// El mes (1–12) que hay que marcar para una fecha «hasta» del ejercicio y; null si no hay fecha o es de otro año
export function monthOf(date, year) {
  const m = /^(\d{4})-(\d{2})-\d{2}$/.exec(date ?? '')
  if (!m || Number(m[1]) !== Number(year)) return null
  return Number(m[2])
}

// Al cambiar de ejercicio, el «hasta» se lleva al mismo mes del nuevo: un fin de mes sigue siendo fin de mes
// (28/02 → 29/02 en bisiesto) y otro día se conserva (o el último del mes, si no existe)
export function moveToYear(date, year) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date ?? '')
  if (!m) return date ?? ''
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])]
  if (d === daysIn(y, mo)) return monthEnd(year, mo)
  return `${year}-${pad(mo)}-${pad(Math.min(d, daysIn(year, mo)))}`
}

// Nombres cortos de los 12 meses en el idioma (Ene, Feb… · Jan, Feb…), sin el punto final de algunos navegadores
export function monthNames(language) {
  const locale = language === 'en' ? 'en-GB' : 'es-ES'
  return Array.from({ length: 12 }, (_, i) => {
    const s = new Date(Date.UTC(2026, i, 1)).toLocaleDateString(locale, { month: 'short', timeZone: 'UTC' }).replace('.', '')
    return s.charAt(0).toUpperCase() + s.slice(1, 3)
  })
}

// Título de un informe en simulación: «SIMULACIÓN · Balance de situación» (Excel, impresión)
export const simTitle = (title, sim, prefix) => (sim ? `${prefix} · ${title}` : title)

// Texto de la franja: cuántos asientos en edición entran
export function simBanner(n, t) {
  if (n == null) return t('sim.loading')
  if (n === 0) return t('sim.none')
  return (n === 1 ? t('sim.one') : t('sim.many')).replace('{n}', n)
}

// La fecha de la que salen «2» o «0102» en el «hasta» de un informe: la fecha ya elegida; si no, la de trabajo si es
// del ejercicio elegido; si no, el último día de ese ejercicio
export function reportBase(toDate, year, work) {
  if (toDate) return toDate
  if (work && Number(String(work).slice(0, 4)) === Number(year)) return work
  return `${year}-12-31`
}
