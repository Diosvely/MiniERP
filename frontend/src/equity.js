// OPERACIONES SOCIETARIAS (v0.42.0): cómo se enseña lo que hace la base de datos (0060 y 0061). Las reglas de la LSC y
// los asientos los decide la base de datos; aquí se preparan los datos y se dibujan los mismos asientos antes de
// contabilizar, para verlos (tests/equity.test.js los compara con los supuestos de referencia S1 a S6).
import { parseAmount } from './practice'

// Las operaciones, en el orden de la vida de una sociedad
export const KINDS = ['incorporation', 'capital_increase', 'reserves_to_capital', 'call', 'distribution',
  'interim_dividend', 'dividend_payment', 'loss_offset', 'capital_reduction']

// Función de la base de datos de cada una (las de reparto y dividendo a cuenta tienen además su vista previa)
export const RPC = {
  incorporation: 'equity_incorporation', capital_increase: 'equity_capital_increase', reserves_to_capital: 'equity_reserves_to_capital',
  call: 'equity_call', distribution: 'equity_distribution', interim_dividend: 'equity_interim_dividend',
  dividend_payment: 'equity_dividend_payment', loss_offset: 'equity_loss_offset', capital_reduction: 'equity_capital_reduction',
}
export const PREVIEW_RPC = { distribution: 'equity_distribution_preview', interim_dividend: 'equity_interim_preview' }

// Formulario vacío de cada operación
export const emptyForm = (kind, legalForm) => ({
  incorporation: { capital: '', paid_pct: legalForm === 'sa' ? '25' : '100' },
  capital_increase: { nominal: '', premium: '', paid_pct: '100' },
  reserves_to_capital: { amount: '', source: '113' },
  call: { amount: '', paid: true },
  distribution: { dividend: '', legal_reserve: '' },
  interim_dividend: { amount: '', estimated_tax: '' },
  dividend_payment: { amount: '', withholding: true, no_withholding_reason: '' },
  loss_offset: { amount: '' },
  capital_reduction: { amount: '' },
}[kind])

const num = (v) => (String(v ?? '').trim() === '' ? undefined : parseAmount(v))
const r2 = (v) => Math.round(v * 100) / 100

// Lo que se manda a la base de datos: { company_id, date, …campos de la operación } (los vacíos no se mandan:
// la base de datos pone su valor por defecto, p. ej. la reserva legal obligatoria o el impuesto estimado al 25 %)
export function payload(kind, form, companyId, date) {
  const p = { company_id: companyId, date }
  const set = (k, v) => { if (v !== undefined && v !== '') p[k] = v }
  if (kind === 'incorporation') { set('capital', num(form.capital)); set('paid_pct', num(form.paid_pct)) }
  if (kind === 'capital_increase') { set('nominal', num(form.nominal)); set('premium', num(form.premium)); set('paid_pct', num(form.paid_pct)) }
  if (kind === 'reserves_to_capital') { set('amount', num(form.amount)); set('source', form.source) }
  if (kind === 'call') { set('amount', num(form.amount)); p.paid = Boolean(form.paid) }
  if (kind === 'distribution') { set('dividend', num(form.dividend)); set('legal_reserve', num(form.legal_reserve)) }
  if (kind === 'interim_dividend') { set('amount', num(form.amount)); set('estimated_tax', num(form.estimated_tax)) }
  if (kind === 'dividend_payment') {
    set('amount', num(form.amount))
    if (!form.withholding) set('no_withholding_reason', String(form.no_withholding_reason ?? '').trim())
  }
  if (kind === 'loss_offset' || kind === 'capital_reduction') set('amount', num(form.amount))
  return p
}

// Reserva legal que toca (art. 274 LSC; SL de menos de 3.000 €: art. 4.2) — la misma regla que erp.equity_legal_reserve
export function legalReserve(form, capital, reserve, profit) {
  if (profit <= 0) return 0
  if (form === 'sl' && capital < 3000) return Math.max(0, Math.min(r2(profit * 0.2), 3000 - capital - reserve))
  return Math.max(0, Math.min(r2(profit * 0.1), r2(capital * 0.2) - reserve))
}

const L = (account, debit, credit) => ({ account, debit: r2(debit || 0), credit: r2(credit || 0) })
const clean = (lines) => lines.filter((l) => l.debit || l.credit)

// Los asientos que hará «Contabilizar» (los mismos que la base de datos), con lo que hay en el formulario.
//   status: erp.equity_status · prev: la vista previa del reparto o del dividendo a cuenta (de la base de datos)
//   → [{ key, lines: [{ account, debit, credit }] }]   (vacío si aún faltan datos)
export function previewEntries(kind, form, status = {}, prev = null) {
  const out = (key, lines) => ({ key, lines: clean(lines) })
  if (kind === 'incorporation' || kind === 'capital_increase') {
    const nominal = num(kind === 'incorporation' ? form.capital : form.nominal) ?? 0
    const premium = kind === 'capital_increase' ? num(form.premium) ?? 0 : 0
    if (nominal <= 0) return []
    const pct = num(form.paid_pct) ?? 100
    const paid = r2(nominal * pct / 100) + premium
    return [
      out('issue', [L('190', nominal + premium, 0), L('194', 0, nominal), L('110', 0, premium)]),
      out('subscription', [L('572', paid, 0), L('1030', nominal + premium - paid, 0), L('190', 0, nominal + premium)]),
      out('registration', [L('194', nominal, 0), L('100', 0, nominal)]),
    ]
  }
  const amount = num(form.amount) ?? 0
  if (kind === 'reserves_to_capital') return amount > 0 ? [out('reserves_to_capital', [L(form.source === '110' ? '110' : '113', amount, 0), L('100', 0, amount)])] : []
  if (kind === 'call') {
    if (amount <= 0) return []
    const e = [out('call', [L('5580', amount, 0), L('1030', 0, amount)])]
    return form.paid ? [...e, out('call_payment', [L('572', amount, 0), L('5580', 0, amount)])] : e
  }
  if (kind === 'distribution') {
    if (!prev || !prev.result) return []
    if (prev.result < 0) return [out('distribution', [L('121', -prev.result, 0), L('129', 0, -prev.result)])]
    return [out('distribution', [L('129', prev.result, 0), L('121', 0, prev.offset_losses), L('112', 0, prev.legal_reserve),
      L('557', 0, prev.interim), L('526', 0, prev.complementary), L('113', 0, prev.voluntary)])]
  }
  if (kind === 'interim_dividend') return amount > 0 ? [out('interim_dividend', [L('557', amount, 0), L('526', 0, amount)])] : []
  if (kind === 'dividend_payment') {
    const gross = num(form.amount) ?? Number(status.dividend_payable ?? 0)
    if (gross <= 0) return []
    const wh = form.withholding ? r2(gross * 0.19) : 0
    return [out('dividend_payment', [L('526', gross, 0), L('47512', 0, wh), L('572', 0, gross - wh)])]
  }
  if (kind === 'loss_offset') return amount > 0 ? [out('loss_offset', [L('113', amount, 0), L('121', 0, amount)])] : []
  if (kind === 'capital_reduction') return amount > 0 ? [out('capital_reduction', [L('100', amount, 0), L('121', 0, amount)])] : []
  return []
}

// Filas del estado del patrimonio neto (signo: + suma, − resta del patrimonio neto)
export const STATUS_ROWS = [
  ['capital', 1], ['uncalled', -1], ['premium', 1], ['legal_reserve', 1], ['voluntary_reserves', 1], ['prior_losses', -1],
  ['result_to_distribute', 1], ['interim_dividend', -1],
]

// La operación que se puede deshacer: la última contabilizada (se deshacen de la última a la primera)
export function undoable(ops = []) {
  return [...ops].filter((o) => o.status === 'posted').sort((a, b) => (a.code < b.code ? 1 : -1))[0]?.id ?? null
}

// ¿Cuadra cada asiento? (en céntimos)
export const balanced = (entries) => entries.every((e) =>
  e.lines.reduce((s, l) => s + Math.round(l.debit * 100) - Math.round(l.credit * 100), 0) === 0)
