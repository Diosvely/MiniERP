// FINANCIACIÓN (v0.43.0): cómo se enseña lo que hace la base de datos (0062 y 0063). El cuadro de amortización, el tipo
// de interés efectivo y los asientos los calcula la base de datos (erp.loan_calc, loan_next_instalment…); aquí se
// preparan los datos y se dibujan los mismos asientos antes de contabilizar, para verlos (tests/financing.test.js los
// compara con los supuestos de referencia F1 a F3).
import { parseAmount } from './practice'

export const KINDS = ['loan', 'leasing']
export const FREQUENCIES = [12, 4, 2, 1]   // cuotas al año: mensual, trimestral, semestral, anual

export const emptyForm = (kind = 'loan', date = '') => ({
  kind, description: '', lender: '', lender_type: 'bank', start_date: date, frequency: '12', periods: '',
  rate: '', principal: '', costs: '', fair_value: '', instalment: '', purchase_option: '', useful_years: '',
})

const num = (v) => (String(v ?? '').trim() === '' ? undefined : parseAmount(v))
const r2 = (v) => Math.round((Number(v) || 0) * 100) / 100
// El tipo de interés admite hasta 4 decimales (4,375 %): no se redondea como un importe
export function parseRate(v) {
  const t = String(v ?? '').trim().replace('%', '').replace(',', '.')
  if (t === '') return undefined
  const n = Number(t)
  return Number.isFinite(n) ? Math.round(n * 10000) / 10000 : undefined
}

// Lo que se manda a erp.loan_calc / erp.loan_create (los vacíos no se mandan: la base de datos pone su valor)
export function payload(form, companyId) {
  const p = { company_id: companyId, kind: form.kind, frequency: Number(form.frequency), start_date: form.start_date }
  const set = (k, v) => { if (v !== undefined && v !== '' && !Number.isNaN(v)) p[k] = v }
  set('description', String(form.description ?? '').trim())
  set('lender', String(form.lender ?? '').trim())
  if (form.kind === 'loan') p.lender_type = form.lender_type
  set('periods', num(form.periods))
  set('rate', parseRate(form.rate))
  if (form.kind === 'loan') { set('principal', num(form.principal)); set('costs', num(form.costs)) }
  else {
    set('fair_value', num(form.fair_value)); set('instalment', num(form.instalment)); set('purchase_option', num(form.purchase_option))
    const years = num(form.useful_years)
    if (years) p.useful_life_months = Math.round(years * 12)
  }
  return p
}

// ¿Hay lo mínimo para calcular el cuadro?
export function ready(form) {
  const ok = (v) => (num(v) ?? 0) > 0
  if (!form.start_date || !ok(form.periods)) return false
  return form.kind === 'loan' ? ok(form.principal) : ok(form.fair_value) && ok(form.instalment)
}

// Cuentas por defecto (las que crea la base de datos si no hay): préstamo de un banco, de otro prestamista, o leasing
export function accounts(kind, lenderType = 'bank') {
  if (kind === 'leasing') return { long: '1740', short: '5240', interest: '6623', accrued: '527', asset: '213' }
  return lenderType === 'other'
    ? { long: '1710', short: '5210', interest: '6624', accrued: '528', bank: '572' }
    : { long: '1700', short: '5200', interest: '6623', accrued: '527', bank: '572' }
}

const L = (account, debit, credit) => ({ account, debit: r2(debit), credit: r2(credit) })
const clean = (lines) => lines.filter((l) => l.debit || l.credit)

// Asiento del alta con el cálculo de la base de datos (erp.loan_calc): préstamo 572 / 5200 + 1700 · leasing 213 / 5240 + 1740
export function startEntry(calc, lenderType = 'bank') {
  if (!calc) return []
  const a = accounts(calc.kind, lenderType)
  const net = r2(calc.net_amount); const short = r2(calc.short_part)
  return clean([L(calc.kind === 'leasing' ? a.asset : a.bank, net, 0), L(a.short, 0, short), L(a.long, 0, r2(net - short))])
}

// Asiento de la cuota siguiente (erp.loan_next_instalment, con las cuentas reales del préstamo):
//   préstamo: 527 (lo devengado) + 6623 (el resto de intereses) + 5200 / 1700 (lo que baja la deuda) / 572
//   leasing (factura): las mismas líneas + el impuesto sobre la cuota entera / la entidad (410)
export function instalmentEntry(next, taxRate = 0) {
  if (!next) return []
  const debts = [L(next.accrued_account_no, next.accrued_used, 0), L(next.interest_account_no, next.interest_expense, 0),
    L(next.short_account_no, next.short_part, 0), L(next.long_account_no, next.long_part, 0)]
  if (next.kind !== 'leasing') return clean([...debts, L('572', 0, next.payment)])
  const tax = r2(Number(next.payment) * Number(taxRate) / 100)
  return clean([L(next.short_account_no, next.short_part, 0), L(next.long_account_no, next.long_part, 0),
    L(next.accrued_account_no, next.accrued_used, 0), L(next.interest_account_no, next.interest_expense, 0),
    L('472', tax, 0), L('410', 0, r2(Number(next.payment) + tax))])
}

// El movimiento que se puede deshacer: el último contabilizado (del último al primero)
export function undoable(events = []) {
  return [...events].filter((e) => e.status === 'posted').sort((a, b) => Number(b.seq) - Number(a.seq))[0]?.id ?? null
}

// Cuotas pagadas (para marcar el cuadro)
export const paidCount = (events = []) => events.filter((e) => e.kind === 'payment' && e.status === 'posted').length

// ¿Cuadra cada asiento? (en céntimos)
export const balanced = (lines) => lines.reduce((s, l) => s + Math.round(l.debit * 100) - Math.round(l.credit * 100), 0) === 0

// El tipo de IVA / IGIC por defecto para la cuota del leasing: el general del territorio
export function defaultTax(codes = []) {
  const ok = codes.filter((c) => !c.blocked && Number(c.rate_pct) > 0 && !['reverse_charge', 'intra_eu_acquisition', 'retail_surcharge'].includes(c.rate_category))
  return (ok.find((c) => c.tax_code === 'IGIC7') ?? ok.find((c) => c.tax_code === 'VAT21') ?? ok[0])?.tax_code ?? ''
}

// El nombre de una cuenta del asiento (por su prefijo: 52400001 → 5240)
const NAMED = ['1700', '1710', '1740', '5200', '5210', '5240', '6623', '6624', '527', '528', '213', '472', '410', '572']
export const accountKey = (no) => NAMED.find((p) => String(no ?? '').startsWith(p)) ?? null
