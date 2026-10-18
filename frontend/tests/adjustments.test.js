import { describe, expect, it } from 'vitest'
import { accrualAmount, accrualLines, adjustmentTotals, checklistSummary, deductibleFrom, defaultSubaccount, excessPrefix, globalPreview,
         impairmentAmount, inventoryLines, isDeductible, nextDay, provisionApplicationLines, provisionPrefix, provisionRevisionLines,
         tierOf } from '../src/adjustments'

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

// v0.37.0 · las cifras de los supuestos de la base de datos (fases 40 y 42)
describe('provisiones (supuesto de la fase 40)', () => {
  it('cuenta según tipo y plazo', () => {
    expect([provisionPrefix('liabilities', 'long'), provisionPrefix('liabilities', 'short'), provisionPrefix('taxes', 'long'),
            provisionPrefix('taxes', 'short'), provisionPrefix('commercial', 'long')]).toEqual(['142', '5293', '141', '5292', '4999'])
    expect(excessPrefix('liabilities')).toBe('7953')
  })
  it('revisión: el litigio sube 3.000; las garantías revierten la anterior y dotan la nueva', () => {
    expect(provisionRevisionLines('liabilities', '14200001', '67800001', '79530001', 12000, 15000)).toEqual([
      { account_no: '67800001', debit: 3000, credit: 0 }, { account_no: '14200001', debit: 0, credit: 3000 }])
    expect(provisionRevisionLines('liabilities', '14200001', '67800001', '79530001', 15000, 14000)).toEqual([
      { account_no: '14200001', debit: 1000, credit: 0 }, { account_no: '79530001', debit: 0, credit: 1000 }])
    expect(provisionRevisionLines('commercial', '49990001', '69590001', '79540001', 1000, 1200)).toEqual([
      { account_no: '49990001', debit: 1000, credit: 0 }, { account_no: '79540001', debit: 0, credit: 1000 },
      { account_no: '69590001', debit: 1200, credit: 0 }, { account_no: '49990001', debit: 0, credit: 1200 }])
  })
  it('aplicación: la sentencia de 14.000 sobre 15.000 deja 1.000 de exceso; el acta de 3.200 sobre 3.000, 200 más de gasto', () => {
    expect(provisionApplicationLines('52930001', '67800001', '79530001', '57200001', 15000, 14000)).toEqual([
      { account_no: '52930001', debit: 15000, credit: 0 }, { account_no: '57200001', debit: 0, credit: 14000 }, { account_no: '79530001', debit: 0, credit: 1000 }])
    expect(provisionApplicationLines('52920001', '63300001', '79520001', '57200001', 3000, 3200)).toEqual([
      { account_no: '52920001', debit: 3000, credit: 0 }, { account_no: '63300001', debit: 200, credit: 0 }, { account_no: '57200001', debit: 0, credit: 3200 }])
  })
})
describe('existencias (supuesto de la fase 42)', () => {
  it('2027: baja de los 8.000 iniciales, alta de los 6.000, reversión del deterioro (793) y materias primas a cero', () => {
    const rows = [{ account_no: '30000001', initial_value: 8000, prev_impairment: 500, variation_account_no: '610' },
                  { account_no: '31000001', initial_value: 2000, prev_impairment: 0, variation_account_no: '611' }]
    const { lines, variation } = inventoryLines(rows, { '30000001': { final: '6000' }, '31000001': { final: '0' } })
    expect(lines.map((l) => `${l.account_no} ${l.debit ? 'D ' + l.debit : 'H ' + l.credit}`).join(' | '))
      .toBe('61000001 D 8000 | 30000001 H 8000 | 30000001 D 6000 | 61000001 H 6000 | 39000001 D 500 | 79310001 H 500 | 61100001 D 2000 | 31000001 H 2000')
    expect(variation).toBe(-4000)
  })
  it('2026: deterioro de 500 en mercaderías (693 / 390)', () => {
    const { lines } = inventoryLines([{ account_no: '30000001', initial_value: 0, prev_impairment: 0, variation_account_no: '610' }],
      { '30000001': { final: 8000, impairment: '500' } })
    expect(lines.slice(2)).toEqual([{ account_no: '69310001', debit: 500, credit: 0 }, { account_no: '39000001', debit: 0, credit: 500 }])
  })
  it('asistente: listo cuando no falta nada', () => {
    expect(checklistSummary([{ status: 'done' }, { status: 'review' }, { status: 'na' }])).toEqual({ done: 1, pending: 0, review: 1, na: 1, ready: true })
    expect(checklistSummary([{ status: 'pending' }]).ready).toBe(false)
  })
})
