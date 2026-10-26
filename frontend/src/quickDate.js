// FECHA RÁPIDA (v0.47.0, mejora de uso 8): como en ContaSol, basta con escribir el día y el mes y el año salen de la
// fecha de trabajo (el mes abierto). Todo se guarda en ISO (aaaa-mm-dd); en pantalla, dd/mm/aaaa.
//   «2» o «02»          → día 2 del mes de trabajo
//   «15/3», «15-3», «1503» → 15 de marzo del año de trabajo
//   «150325», «15/3/25» → 15/03/2025 · «15032025» o «15/3/2025» → 15/03/2025
//   «h» → hoy · «2026-03-15» (ISO) se acepta tal cual
// Lo que no es una fecha real (31/02, 00/05…) devuelve null.

const pad = (n) => String(n).padStart(2, '0')
const iso = (y, m, d) => {
  const dt = new Date(Date.UTC(y, m - 1, d))
  return dt.getUTCFullYear() === y && dt.getUTCMonth() === m - 1 && dt.getUTCDate() === d ? `${y}-${pad(m)}-${pad(d)}` : null
}
const year4 = (y) => (y < 100 ? 2000 + y : y)

// base: la fecha de trabajo en ISO · today: hoy en ISO (para «h»)
export function parseQuickDate(text, base, today) {
  const s = String(text ?? '').trim().toLowerCase()
  if (!s) return null
  if (s === 'h' || s === 'hoy' || s === 't' || s === 'today') return today ?? null
  const [by, bm] = String(base ?? today ?? '').split('-').map(Number)
  let m
  if ((m = s.match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/))) return iso(+m[1], +m[2], +m[3])
  if ((m = s.match(/^(\d{1,2})(?:[/.-](\d{1,2})(?:[/.-](\d{2}|\d{4}))?)?$/))) {
    return iso(m[3] ? year4(+m[3]) : by, m[2] ? +m[2] : bm, +m[1])
  }
  if (/^\d+$/.test(s)) {
    if (s.length === 3) return iso(by, +s.slice(2), +s.slice(0, 2))                       // 153 → 15/3
    if (s.length === 4) return iso(by, +s.slice(2, 4), +s.slice(0, 2))                    // 1503
    if (s.length === 6) return iso(year4(+s.slice(4)), +s.slice(2, 4), +s.slice(0, 2))     // 150325
    if (s.length === 8) return iso(+s.slice(4), +s.slice(2, 4), +s.slice(0, 2))           // 15032025
  }
  return null
}

// ISO → dd/mm/aaaa
export const showDate = (v) => (v && /^\d{4}-\d{2}-\d{2}$/.test(v) ? `${v.slice(8, 10)}/${v.slice(5, 7)}/${v.slice(0, 4)}` : '')

// Un día más o menos (flechas ↑ ↓)
export function addDays(v, n) {
  const [y, m, d] = v.split('-').map(Number)
  const dt = new Date(Date.UTC(y, m - 1, d + n))
  return `${dt.getUTCFullYear()}-${pad(dt.getUTCMonth() + 1)}-${pad(dt.getUTCDate())}`
}

// ¿Cae fuera del mes abierto? (solo en la contabilidad mes a mes) → 'before' | 'after' | null
export function outsideMonth(v, range) {
  if (!v || !range?.from || !range?.to) return null
  return v < range.from ? 'before' : v > range.to ? 'after' : null
}
