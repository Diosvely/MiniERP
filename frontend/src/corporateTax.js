// IMPUESTO SOBRE SOCIEDADES (v0.41.0): cómo se enseña el cálculo que hace la base de datos (0057 y 0058)
import { cents } from './assets'

export const REGIMES = ['general', 'erd', 'micro', 'new_entity']

// Signo de un ajuste: + aumenta la base, − la disminuye
export const sign = (a) => (a.direction === 'increase' ? 1 : -1)

// Del resultado contable a la cuota diferencial, en el orden de la declaración (modelo 200)
export function breakdown(c) {
  if (!c) return []
  return [
    { key: 'preTax', amount: c.pre_tax_result },
    { key: 'permanent', amount: c.permanent, adj: true },
    { key: 'tempIncrease', amount: c.temporary_increase, adj: true },
    { key: 'tempDecrease', amount: -c.temporary_decrease, adj: true },
    { key: 'baseBefore', amount: c.base_before_losses, total: true },
    { key: 'losses', amount: -c.losses_compensated, adj: true },
    { key: 'taxableBase', amount: c.taxable_base, total: true },
    { key: 'quota', amount: c.quota },
    { key: 'withholdings', amount: -c.withholdings, adj: true },
    { key: 'differential', amount: c.differential, total: true },
  ]
}

// Del impuesto al resultado del ejercicio (NRV 13.ª: gasto = corriente + diferido)
export function expense(c) {
  if (!c) return []
  return [
    { key: 'current', amount: c.current_tax },
    { key: 'deferred', amount: c.deferred_tax },
    { key: 'expense', amount: c.tax_expense, total: true },
    { key: 'netResult', amount: c.net_result, total: true },
  ]
}

const line = (account, debit, credit) => ({ account, debit: Math.round(debit * 100) / 100, credit: Math.round(credit * 100) / 100 })

// Los dos asientos que hará «Contabilizar» (los mismos que erp.corporate_tax_post), para verlos antes
export function entriesPreview(c) {
  if (!c) return { current: [], deferred: [] }
  const r = (v) => cents(v) / 100
  const current = []
  if (r(c.current_tax) > 0) current.push(line('6300', r(c.current_tax), 0))
  // v0.42.0: el impuesto que ahorran los gastos cargados a reservas, a reservas
  if (r(c.equity_tax_effect) > 0) current.push(line('113', 0, r(c.equity_tax_effect)))
  if (r(c.withholdings) !== 0) current.push(line('473', Math.max(-r(c.withholdings), 0), Math.max(r(c.withholdings), 0)))
  if (r(c.differential) > 0) current.push(line('4752', 0, r(c.differential)))
  if (r(c.differential) < 0) current.push(line('4709', -r(c.differential), 0))
  const deferred = []
  const rate = Number(c.deferred_rate) / 100
  const net = Math.round(r(c.temporary_increase) * rate * 100) / 100 - Math.round(r(c.temporary_decrease) * rate * 100) / 100
  if (net !== 0) deferred.push(line('4740', Math.max(net, 0), Math.max(-net, 0)))
  if (r(c.loss_credit) > 0 || r(c.loss_credit_used) > 0) deferred.push(line('4745', r(c.loss_credit), r(c.loss_credit_used)))
  if (r(c.deferred_tax) !== 0) deferred.push(line('6301', Math.max(r(c.deferred_tax), 0), Math.max(-r(c.deferred_tax), 0)))
  return { current, deferred }
}

// ¿Cuadra un asiento? (debe = haber, al céntimo)
export const balanced = (lines) => lines.reduce((s, l) => s + cents(l.debit) - cents(l.credit), 0) === 0
