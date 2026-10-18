import { describe, expect, it } from 'vitest'
import { accrualAmount, accrualLines, adjustmentTotals, deductibleFrom, defaultSubaccount, globalPreview, impairmentAmount,
         isDeductible, nextDay, tierOf } from '../src/adjustments'

// Las cifras del supuesto de referencia de la base de datos (fase 38, Comercial Atlántico SL)
describe('periodificaciones (supuesto de la fase 38)', () => {
  it('seguro anual del 01/10: 9/12 de 1.200 = 900 anticipado; mantenimiento nov-ene: 2/3 de 900 = 600 devengado', () => {
    expect(accrualAmount('prepaid_expense', '1200', '2026-10-01', 12, '2026-12-31')).toBe(900)
    expect(accrualAmount('deferred_income', '6000', '2026-11-01', 6, '2026-12-31')).toBe(4000)
    expect(accrualAmount('accrued_income', '900', '2026-11-01', 3, '2026-12-31')).toBe(600)
    expect(accrualAmount('accrued_expense', '1.200', '2026-11-01', 0, '2026-12-31')).toBe(0)
  })
  it('el primer mes, por días (como la amortización): 1.200 del 16/10 a 12 meses → 2 meses + 16/31 transcurridos', () => {
    expect(accrualAmount('prepaid_expense', '1200', '2026-10-16', 12, '2026-12-31')).toBe(Math.round((1200 - 1200 * (2 + 16 / 31) / 12) * 100) / 100)
  })
  it('el asiento del cierre y su reversión', () => {
    expect(accrualLines('prepaid_expense', '48000001', '62500001', 900)).toEqual([
      { account_no: '48000001', debit: 900, credit: 0 }, { account_no: '62500001', debit: 0, credit: 900 }])
    expect(accrualLines('deferred_income', '48500001', '75200001', 4000)).toEqual([
      { account_no: '75200001', debit: 4000, credit: 0 }, { account_no: '48500001', debit: 0, credit: 4000 }])
    expect(accrualLines('accrued_expense', '40090001', '62800001', 350)).toEqual([
      { account_no: '62800001', debit: 350, credit: 0 }, { account_no: '40090001', debit: 0, credit: 350 }])
    expect(accrualLines('accrued_income', '43090001', '70500001', 600, true)).toEqual([
      { account_no: '70500001', debit: 600, credit: 0 }, { account_no: '43090001', debit: 0, credit: 600 }])
    expect(accrualLines('prepaid_expense', '48000001', '62500001', 0)).toEqual([])
  })
  it('subcuenta por defecto y fecha de la reversión', () => {
    expect(defaultSubaccount('4009')).toBe('40090001')
    expect(defaultSubaccount('480', 9)).toBe('480000001')
    expect(nextDay('2026-12-31')).toBe('2027-01-01')
  })
})

describe('deterioro de clientes (supuesto de la fase 38)', () => {
  it('individual: Dudoso, 50 % de 800 = 400; deducible desde los 6 meses del vencimiento (art. 13.1.a LIS)', () => {
    expect(impairmentAmount(800, '50')).toBe(400)
    expect(impairmentAmount('2420', 100)).toBe(2420)
    expect(deductibleFrom('2026-10-01')).toBe('2027-04-01')
    expect(deductibleFrom('2026-08-31')).toBe('2027-02-28')
    expect(isDeductible('2026-03-15', '2026-12-31')).toBe(true)
    expect(isDeductible('2026-10-01', '2026-12-31')).toBe(false)
  })
  it('tramos de antigüedad', () => {
    expect([0, 1, 90, 91, 180, 181, 365, 366].map(tierOf)).toEqual(['not_due', 'd1_90', 'd1_90', 'd91_180', 'd91_180', 'd181_365', 'd181_365', 'd365_plus'])
  })
  it('global: 25 % de 605 + 10 % de 1.210 = 272,25, sin las deterioradas una a una; tope ERD 1 % de 5.445 = 54,45', () => {
    const items = [
      { invoice_id: 'mor', invoice_type: 'sale', pending: 2420, days_overdue: 291 },
      { invoice_id: 'g1', invoice_type: 'sale', pending: 605, days_overdue: 235 },
      { invoice_id: 'g2', invoice_type: 'sale', pending: 1210, days_overdue: 169 },
      { invoice_id: 'g3', invoice_type: 'sale', pending: 3630, days_overdue: 0 },
      { invoice_id: 'p1', invoice_type: 'purchase', pending: 999, days_overdue: 400 },
      { invoice_id: 'c1', invoice_type: 'sale', pending: 0, days_overdue: 0 }]
    const g = globalPreview(items, new Set(['mor']), { not_due: 0, d1_90: '5', d91_180: '10', d181_365: '25' })
    expect(g.amount).toBe(272.25)
    expect(g.basis).toBe(5445)
    expect(g.erdLimit).toBe(54.45)
    expect(g.rows.find((r) => r.tier === 'd181_365')).toEqual({ tier: 'd181_365', basis: 605, pct: 25, amount: 151.25 })
  })
  it('resumen: periodificaciones por revertir y deterioro vivo', () => {
    expect(adjustmentTotals(
      [{ status: 'active', amount: 900 }, { status: 'active', amount: 4000 }, { status: 'reversed', amount: 350 }],
      [{ status: 'active', amount: 2420 }, { status: 'active', amount: 272.25 }, { status: 'reversed', amount: 400 }]))
      .toEqual({ accruals: 2, accrualAmount: 4900, impairments: 2, impairmentAmount: 2692.25 })
  })
})
