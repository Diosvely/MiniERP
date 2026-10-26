// PANTALLA «ASIENTOS» (v0.47.0, mejora de uso 9): una fila por asiento con su origen y su estado. La lista la da la
// base de datos (erp.entries_list, 0070); aquí, los filtros, los totales y lo que se puede hacer con cada fila.

export const RANGES = ['month', 'range', 'all']
export const STATES = ['posted', 'ok', 'error']
export const PAGE = 200

// Mes actual: el mes abierto (contabilidad mes a mes) o el mes de la fecha de trabajo
export function monthRange(workDate, workMonth) {
  if (workMonth?.from && workMonth?.to) return { from: workMonth.from, to: workMonth.to }
  const [y, m] = String(workDate).split('-').map(Number)
  const last = new Date(Date.UTC(y, m, 0)).getUTCDate()
  return { from: `${y}-${String(m).padStart(2, '0')}-01`, to: `${y}-${String(m).padStart(2, '0')}-${String(last).padStart(2, '0')}` }
}

// Fechas que se piden a la base de datos según el botón
export function rangeDates(range, { workDate, workMonth, from, to }) {
  if (range === 'all') return { from: null, to: null }
  if (range === 'range') return { from: from || null, to: to || null }
  return monthRange(workDate, workMonth)
}

const norm = (s) => String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()

// Filtros de la pantalla: estado, origen y texto (nº, concepto o documento)
export function filterEntries(rows, { state = '', source = '', text = '' } = {}) {
  const q = norm(text).trim()
  return (rows ?? []).filter((r) => (!state || r.state === state) && (!source || r.source === source)
    && (!q || String(r.entry_no ?? '') === q || norm(r.description).includes(q) || norm(r.document_no).includes(q)))
}

// Totales y cuentas por estado
export function summary(rows) {
  const s = { debit: 0, credit: 0, posted: 0, ok: 0, error: 0 }
  for (const r of rows ?? []) { s.debit += Number(r.total_debit) || 0; s.credit += Number(r.total_credit) || 0; s[r.state] = (s[r.state] ?? 0) + 1 }
  s.debit = Math.round(s.debit * 100) / 100; s.credit = Math.round(s.credit * 100) / 100
  return s
}

// Orígenes que hay en la lista (para el desplegable)
export const sourcesOf = (rows) => [...new Set((rows ?? []).map((r) => r.source))].sort()

// Adónde lleva el clic: un contabilizado, a su ficha; un borrador, a Nuevo asiento para seguir con él
export const rowTarget = (r) => (r.status === 'posted' ? `asiento/${r.fiscal_year}/${r.entry_no}` : `entry/${r.entry_id}`)

// Solo los borradores «en edición» se pueden marcar para contabilizar varios
export const selectable = (r) => r.status === 'draft' && r.state === 'ok'

// Preferencias de este navegador: el botón de fechas elegido
export function savedRange() { try { const r = localStorage.getItem('erp-asientos-rango'); return RANGES.includes(r) ? r : 'month' } catch { return 'month' } }
export function saveRange(r) { try { localStorage.setItem('erp-asientos-rango', r) } catch { /* sin almacenamiento */ } }
