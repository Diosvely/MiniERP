// CASOS COMPLETOS (v0.46.0): un ejercicio entero, de la constitución a las cuentas anuales, que la base de datos carga
// en una empresa nueva con las funciones de cada módulo (erp.create_case_company, 0067) y compara al céntimo con las
// cifras calculadas a mano (erp.case_compare). Aquí, lo que la pantalla necesita para ordenarlo y nombrarlo.

// Modos de carga: «completo» (con el cierre hecho) o «hasta el cierre» (el cierre lo hace quien estudia)
export const MODES = ['full', 'until_closing']

// Grupos de la comparación, en el orden de las cuentas anuales, y la pantalla donde se ve cada uno
export const KINDS = [
  ['pyg', 'pyg'], ['balance', 'balance'], ['ecpn', 'ecpn'], ['cf_indirect', 'cashflow'], ['cf_direct', 'cashflow'],
  ['cit', 'corporate_tax'], ['tax_form', 'forms'], ['withholding', 'withholdings'],
]
export const screenOf = (kind) => KINDS.find(([k]) => k === kind)?.[1] ?? 'reports'

// Las filas de la comparación, por grupo, con sus cuentas: ok, pendiente y diferencia
export function groupCompare(rows) {
  return KINDS.map(([kind, screen]) => {
    const rs = (rows ?? []).filter((r) => r.kind === kind)
    return { kind, screen, rows: rs, ...counts(rs) }
  }).filter((g) => g.rows.length)
}

export function counts(rows) {
  const c = { total: 0, ok: 0, pending: 0, diff: 0 }
  for (const r of rows ?? []) { c.total++; c[r.status] = (c[r.status] ?? 0) + 1 }
  return c
}

// Estado de un grupo o de toda la comparación: diferencia si hay alguna; si no, pendiente si hay alguna; si no, ok
export const overall = (c) => (c.diff ? 'diff' : c.pending ? 'pending' : 'ok')

// Operaciones hechas, y las del año y las del cierre por separado
export function progress(steps) {
  const s = steps ?? []
  return {
    done: s.filter((x) => x.status === 'done').length,
    total: s.length,
    year: s.filter((x) => x.phase === 'year'),
    closing: s.filter((x) => x.phase === 'closing'),
  }
}

// Nombre de una partida. Las de los estados los trae la base de datos; las del ECPN, el impuesto y los modelos, aquí.
const ECPN_A = { result: 'result', b_grants: 'b_grants', b_tax: 'b_tax', b_total: 'b_total', c_grants: 'c_grants', c_tax: 'c_tax', c_total: 'c_total', total: 'total' }
const CIT = { pre_tax_result: 'preTax', taxable_base: 'taxableBase', quota: 'quota', tax_expense: 'expense', differential: 'differential' }
export function rowLabel(r, t, language, year = '') {
  const db = language === 'en' ? (r.label_en ?? r.label) : r.label
  if (db) return db.trim()
  const [a, b, c] = String(r.code).split('.')
  if (r.kind === 'ecpn') {
    if (a === 'part_a' && ECPN_A[b]) return t(`ecpn.a.${ECPN_A[b]}`)
    if (a === 'part_b') return `${t(`ecpn.row.${b}`)} · ${t(`ecpn.col.${c}`)}`
    if (a === 'start' || a === 'end') return t(`ecpn.row.${a}`).replace('{y}', year)
    return t(`cs.code.${a}`)
  }
  if (r.kind === 'cit') return CIT[a] ? t(`ct.row.${CIT[a]}`) : t(`cs.code.${a}`)
  if (r.kind === 'tax_form') return t('cs.box').replace('{q}', a).replace('{b}', b)
  if (r.kind === 'withholding') return t('cs.form').replace('{q}', a).replace('{f}', b)
  return r.code
}

// Enlace a un asiento: #/empresa/<id>/asiento/<año>/<nº>
export const entrySection = (e) => `asiento/${e.year}/${e.entry_no}`

// Lo que se muestra de los asientos de una operación: los primeros y cuántos más
export function entryList(entries, max = 4) {
  const list = entries ?? []
  return { shown: list.slice(0, max), more: Math.max(list.length - max, 0) }
}

// Filas para Excel
export function exportRows(rows, t, language, year) {
  return (rows ?? []).map((r) => ({
    group: t(`cs.kind.${r.kind}`), code: r.code, label: rowLabel(r, t, language, year),
    expected: r.expected, actual: r.actual, difference: r.difference, status: t(`cs.status.${r.status}`),
  }))
}
