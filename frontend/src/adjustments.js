// AJUSTES DE CIERRE (v0.36.0): cálculos de la pantalla. Quien decide y contabiliza es la base de datos (0043); aquí
// solo se prepara lo que se le envía y se enseña antes: el importe, el asiento y los avisos fiscales.
import { accumulatedAt, addMonths, cents } from './assets'

// Los cuatro tipos de periodificación: cuenta de balance, grupo de la cuenta de resultados y lado de cada una
//   (el asiento del cierre; la reversión del año siguiente es el mismo al revés)
export const ACCRUAL_KINDS = {
  prepaid_expense: { balance: '480', group: '6', balanceSide: 'debit' },    // 480 D / 6xx H
  deferred_income: { balance: '485', group: '7', balanceSide: 'credit' },   // 7xx D / 485 H
  accrued_expense: { balance: '4009', group: '6', balanceSide: 'credit' },  // 6xx D / 4009 H
  accrued_income:  { balance: '4309', group: '7', balanceSide: 'debit' },   // 4309 D / 7xx H
}

// Importe a periodificar desde el total y el periodo que cubre (por meses; el primer mes por días, como erp.accrual_elapsed)
//   anticipado (480 / 485) = lo que queda del periodo tras el corte · devengado (4009 / 4309) = lo transcurrido
export function accrualAmount(kind, total, start, months, cutoff) {
  if (!ACCRUAL_KINDS[kind] || !start || !cutoff || !(Number(months) > 0) || !(cents(total) > 0)) return 0
  const elapsed = accumulatedAt(total, 0, months, start, cutoff)
  return kind === 'prepaid_expense' || kind === 'deferred_income' ? Math.round((cents(total) - cents(elapsed))) / 100 : elapsed
}

// Asiento del ajuste (o de su reversión) para la vista previa: [{ account_no, debit, credit }]
export function accrualLines(kind, balanceNo, plNo, amount, reverse = false) {
  const k = ACCRUAL_KINDS[kind]
  const a = Math.round(Number(amount) * 100) / 100
  if (!k || !(a > 0)) return []
  const balanceDebit = (k.balanceSide === 'debit') !== reverse
  const bal = { account_no: balanceNo, debit: balanceDebit ? a : 0, credit: balanceDebit ? 0 : a }
  const pl = { account_no: plNo, debit: balanceDebit ? 0 : a, credit: balanceDebit ? a : 0 }
  return bal.debit ? [bal, pl] : [pl, bal]
}

// Subcuenta por defecto de un prefijo (la que crea la base de datos): 480 → 48000001 con 8 dígitos
export const defaultSubaccount = (prefix, digits = 8) => prefix.padEnd(digits - 1, '0') + '1'

// Día siguiente (la reversión, por defecto)
export function nextDay(isoDate) {
  const [y, m, d] = String(isoDate).slice(0, 10).split('-').map(Number)
  return new Date(Date.UTC(y, m - 1, d + 1)).toISOString().slice(0, 10)
}

// Tramos de antigüedad del deterioro global (los mismos que erp.global_impairment_calc)
export const TIERS = ['not_due', 'd1_90', 'd91_180', 'd181_365', 'd365_plus']
export function tierOf(daysOverdue) {
  const d = Number(daysOverdue) || 0
  return d <= 0 ? 'not_due' : d <= 90 ? 'd1_90' : d <= 180 ? 'd91_180' : d <= 365 ? 'd181_365' : 'd365_plus'
}

// Vista previa del global: lo pendiente de clientes por tramo × su % (sin las facturas con deterioro individual)
//   items: open_items de ventas · impaired: ids de facturas con deterioro individual activo · rates: { tier: % }
export function globalPreview(items, impaired, rates) {
  const rows = TIERS.map((tier) => ({ tier, basis: 0, pct: Number(String(rates?.[tier] ?? '').replace(',', '.')) || 0, amount: 0 }))
  for (const i of items) {
    if (i.invoice_type !== 'sale' || !(Number(i.pending) > 0) || impaired.has(i.invoice_id)) continue
    rows[TIERS.indexOf(tierOf(i.days_overdue))].basis += cents(i.pending)
  }
  for (const r of rows) { r.amount = Math.round(r.basis * r.pct / 100) / 100; r.basis /= 100 }
  const basis = rows.reduce((s, r) => s + cents(r.basis), 0) / 100
  return { rows, basis, amount: rows.reduce((s, r) => s + cents(r.amount), 0) / 100, erdLimit: Math.round(basis) / 100 }
}

// Deterioro individual: importe (pendiente × %) y desde cuándo es deducible (6 meses desde el vencimiento, art. 13.1.a LIS)
export const impairmentAmount = (pending, pct) => Math.round(cents(pending) * (Number(String(pct).replace(',', '.')) || 0) / 100) / 100
export const deductibleFrom = (dueDate) => (dueDate ? addMonths(dueDate, 6) : null)
export const isDeductible = (dueDate, date) => !!dueDate && !!date && date >= deductibleFrom(dueDate)

// Resumen de la cabecera: periodificaciones pendientes de revertir y deterioro vivo (lo que hay en la 490)
export function adjustmentTotals(accruals, impairments) {
  const pending = accruals.filter((a) => a.status === 'active')
  const live = impairments.filter((i) => i.status === 'active')
  return {
    accruals: pending.length, accrualAmount: pending.reduce((s, a) => s + cents(a.amount), 0) / 100,
    impairments: live.length, impairmentAmount: live.reduce((s, i) => s + cents(i.amount), 0) / 100,
  }
}

// ---------------------------------------------------------------------------------------------------------------
// PROVISIONES (v0.37.0, 0045): cuenta según el tipo y el plazo, y la vista previa de la revisión
export const PROVISION_KINDS = ['liabilities', 'taxes', 'commercial']
export function provisionPrefix(kind, term) {
  if (kind === 'commercial') return '4999'
  if (kind === 'taxes') return term === 'short' ? '5292' : '141'
  return term === 'short' ? '5293' : '142'
}
export const excessPrefix = (kind) => ({ taxes: '7952', liabilities: '7953', commercial: '7954' })[kind]

// Revisión: si sube, gasto D / provisión H; si baja, provisión D / exceso H. Las comerciales (499), según el PGC,
// revierten toda la anterior (7954) y dotan la nueva (6959): no se contabiliza la diferencia neta.
export function provisionRevisionLines(kind, provisionNo, expenseNo, excessNo, oldAmount, newAmount) {
  const o = cents(oldAmount) / 100, n = cents(newAmount) / 100
  if (kind === 'commercial') {
    return [{ account_no: provisionNo, debit: o, credit: 0 }, { account_no: excessNo, debit: 0, credit: o },
            { account_no: expenseNo, debit: n, credit: 0 }, { account_no: provisionNo, debit: 0, credit: n }].filter((l) => l.debit || l.credit)
  }
  const d = Math.round((n - o) * 100) / 100
  if (d > 0) return [{ account_no: expenseNo, debit: d, credit: 0 }, { account_no: provisionNo, debit: 0, credit: d }]
  if (d < 0) return [{ account_no: provisionNo, debit: -d, credit: 0 }, { account_no: excessNo, debit: 0, credit: -d }]
  return []
}

// Aplicación: provisión D por su saldo; lo pagado al banco; la diferencia, al gasto (si se paga más) o al exceso
export function provisionApplicationLines(provisionNo, expenseNo, excessNo, cashNo, balance, paid) {
  const b = cents(balance) / 100, p = cents(paid) / 100, d = Math.round((p - b) * 100) / 100
  return [{ account_no: provisionNo, debit: b, credit: 0 }, { account_no: expenseNo, debit: Math.max(d, 0), credit: 0 },
          { account_no: cashNo, debit: 0, credit: p }, { account_no: excessNo, debit: 0, credit: Math.max(-d, 0) }]
    .filter((l) => l.debit || l.credit)
}

// ---------------------------------------------------------------------------------------------------------------
// EXISTENCIAS (v0.37.0, 0047): el asiento del inventario del cierre, cuenta por cuenta
//   rows: erp.inventory_preview { account_no, initial_value, prev_impairment, variation_account_no }
//   counts: { [account_no]: { final, impairment } } · digits: dígitos de las subcuentas
const invPrefix = (no, kind) => {
  const d = String(no)[1]
  const n = { 0: '1', 1: '2', 2: '3' }[d] ?? '0'
  return { allowance: '39' + d, expense: '693' + n, reversal: '793' + n }[kind]
}
export function inventoryLines(rows, counts, digits = 8) {
  const out = []
  let variation = 0
  for (const r of rows) {
    const c = counts[r.account_no] ?? {}
    const init = cents(r.initial_value) / 100, fin = cents(c.final) / 100, imp = cents(c.impairment) / 100, prev = cents(r.prev_impairment) / 100
    const v = defaultSubaccount(r.variation_account_no, digits)
    if (init) out.push({ account_no: v, debit: Math.max(init, 0), credit: Math.max(-init, 0) }, { account_no: r.account_no, debit: Math.max(-init, 0), credit: Math.max(init, 0) })
    if (fin) out.push({ account_no: r.account_no, debit: fin, credit: 0 }, { account_no: v, debit: 0, credit: fin })
    if (prev) out.push({ account_no: defaultSubaccount(invPrefix(r.account_no, 'allowance'), digits), debit: prev, credit: 0 },
                       { account_no: defaultSubaccount(invPrefix(r.account_no, 'reversal'), digits), debit: 0, credit: prev })
    if (imp) out.push({ account_no: defaultSubaccount(invPrefix(r.account_no, 'expense'), digits), debit: imp, credit: 0 },
                      { account_no: defaultSubaccount(invPrefix(r.account_no, 'allowance'), digits), debit: 0, credit: imp })
    variation += cents(fin) - cents(init)
  }
  return { lines: out, variation: variation / 100 }
}

// ---------------------------------------------------------------------------------------------------------------
// ASISTENTE DE CIERRE (v0.37.0): resumen de los pasos (hechos / faltan / revisar / no aplica)
export function checklistSummary(steps) {
  const s = { done: 0, pending: 0, review: 0, na: 0 }
  for (const x of steps) s[x.status] = (s[x.status] ?? 0) + 1
  return { ...s, ready: s.pending === 0 }
}
