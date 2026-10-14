import { describe, it, expect } from 'vitest'
import { buildApplications, linkCandidates, partnersWithPending, previewEntry } from '../src/payments.js'

const items = [
  { invoice_id: 'a', invoice_no: 'C-1', invoice_type: 'purchase', partner_id: 'p1', partner_name: 'Abogada', partner_account_no: '41000001', pending: 560, days_overdue: 40 },
  { invoice_id: 'b', invoice_no: 'C-2', invoice_type: 'purchase', partner_id: 'p1', partner_name: 'Abogada', partner_account_no: '41000001', pending: 1210.1, days_overdue: 0 },
  { invoice_id: 'c', invoice_no: 'C-3', invoice_type: 'purchase', partner_id: 'p2', partner_name: 'Asesoría', partner_account_no: '41000002', pending: 99, days_overdue: 0 },
  { invoice_id: 'd', invoice_no: 'C-4', invoice_type: 'purchase', partner_id: 'p2', partner_name: 'Asesoría', partner_account_no: '41000002', pending: 0, days_overdue: null },
  { invoice_id: 'e', invoice_no: 'F-1', invoice_type: 'sale', partner_id: 'p3', partner_name: 'Cliente', partner_account_no: '43000001', pending: 2420, days_overdue: 5 },
]

describe('cobros y pagos (v0.32.0)', () => {
  it('terceros con facturas pendientes: el más vencido primero, con su total sin errores de céntimos', () => {
    const p = partnersWithPending(items, 'purchase')
    expect(p.map((x) => x.name)).toEqual(['Abogada', 'Asesoría'])
    expect(p[0]).toMatchObject({ pending: 1770.1, invoices: 2, maxOverdue: 40 })
    expect(p[1].invoices).toBe(1)   // la pagada no cuenta
    expect(partnersWithPending(items, 'sale').map((x) => x.name)).toEqual(['Cliente'])
  })
  it('importes en formato español; avisa de cero y de pagar de más', () => {
    const own = items.filter((i) => i.partner_id === 'p1')
    expect(buildApplications({ a: '560', b: '1.210,10'.replace('.', '') }, own)).toEqual({
      apps: [{ invoice_id: 'a', amount: 560 }, { invoice_id: 'b', amount: 1210.1 }], total: 1770.1, errors: [] })
    expect(buildApplications({ a: '600' }, own).errors).toEqual([{ invoice: 'C-1', code: 'tooMuch' }])
    expect(buildApplications({ a: '0' }, own).errors).toEqual([{ invoice: 'C-1', code: 'zero' }])
  })
  it('el asiento: pago 410 al Debe / 572 al Haber · cobro 572 al Debe / 430 al Haber', () => {
    expect(previewEntry('payment', '41000001', '57200001', 500)).toEqual([
      { account_no: '41000001', debit: 500, credit: 0 }, { account_no: '57200001', debit: 0, credit: 500 }])
    expect(previewEntry('collection', '43000001', '57000001', 10)[0]).toEqual({ account_no: '57000001', debit: 10, credit: 0 })
  })
  it('para vincular: solo asientos manuales en el lado del pago, marcando los ya vinculados', () => {
    const lines = [
      { entry_id: 'x', fiscal_year: 2026, entry_no: 7, posting_date: '2026-05-02', description: 'Transferencia', debit: 242, credit: 0, source: 'manual' },
      { entry_id: 'y', fiscal_year: 2026, entry_no: 3, posting_date: '2026-04-10', description: 'Factura', debit: 0, credit: 363, source: 'invoice' },
      { entry_id: 'z', fiscal_year: 2026, entry_no: 9, posting_date: '2026-05-20', description: 'Pago a cuenta', debit: 100, credit: 0, source: 'manual' },
    ]
    const c = linkCandidates(lines, 'payment', new Set(['2026/7']))
    expect(c.map((x) => [x.entry_no, x.amount, x.linked])).toEqual([[9, 100, false], [7, 242, true]])
    expect(linkCandidates(lines, 'collection')).toEqual([])
  })
})

import { agingTotals, difference } from '../src/payments.js'
describe('antigüedad de saldos', () => {
  const rows = [
    { not_due: 0, d1_30: 12.1, d31_60: 0, d61_90: 0, d90_plus: 0, total: 12.1, account_balance: 12.1 },
    { not_due: 0, d1_30: 0, d31_60: 0, d61_90: 0, d90_plus: 605, total: 605, account_balance: 505 },
  ]
  it('totales sin errores de céntimos y terceros que no cuadran con su cuenta', () => {
    expect(agingTotals(rows)).toMatchObject({ d1_30: 12.1, d90_plus: 605, total: 617.1, account_balance: 517.1, unmatched: 1 })
    expect(difference(rows[1])).toBe(-100)
    expect(difference(rows[0])).toBe(0)
  })
})
