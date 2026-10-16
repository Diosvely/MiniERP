import { describe, expect, it } from 'vitest'
import { accumulatedAt, addMonths, annualPct, assetTotals, classesFor, endOfMonth, invoiceAssetLines, isAssetAccount, taxWarnings } from '../src/assets'

// Las cifras son las del supuesto de referencia de la fase 36 (calculadas a mano desde la NRV 2.ª y 3.ª)
describe('inmovilizado', () => {
  it('% anual y avisos fiscales (art. 12.1.a LIS)', () => {
    expect(annualPct(48)).toBe(25)
    expect(annualPct(96)).toBe(12.5)
    const informatica = { max_pct: 25, max_years: 8 }
    expect(taxWarnings(informatica, 48)).toEqual([])
    expect(taxWarnings(informatica, 24)).toEqual([{ code: 'above_tax_max', rate: 50, max: 25 }])
    expect(taxWarnings(informatica, 120)[0]).toMatchObject({ code: 'below_tax_min', maxYears: 8 })
    expect(taxWarnings(null, 24)).toEqual([])
  })
  it('meses como PostgreSQL', () => {
    expect(addMonths('2026-01-31', 1)).toBe('2026-02-28')
    expect(addMonths('2026-03-15', 9)).toBe('2026-12-15')
    expect(endOfMonth('2028-02-10')).toBe('2028-02-29')
  })
  it('amortización acumulada: lineal por meses, el primer mes por días', () => {
    expect(accumulatedAt(1200, 0, 48, '2026-07-01', '2026-12-31')).toBe(150)          // 6 meses × 25
    expect(accumulatedAt(18000, 2000, 96, '2026-03-15', '2026-12-31')).toBe(1591.40)   // 9 meses + 17/31
    expect(accumulatedAt(18000, 2000, 96, '2026-03-15', '2027-06-30')).toBe(2588.89)   // 15 meses + 16/30
    expect(accumulatedAt(1200, 0, 48, '2026-07-01', '2035-01-01')).toBe(1200)         // nunca más que la base
    expect(accumulatedAt(1200, 0, 48, '2026-07-01', '2026-06-30')).toBe(0)
  })
  it('cuentas amortizables: 20x / 21x / 22x salvo los terrenos', () => {
    expect(isAssetAccount('21700001')).toBe(true)
    expect(isAssetAccount('20600001')).toBe(true)
    expect(isAssetAccount('21000001')).toBe(false)
    expect(isAssetAccount('22000001')).toBe(false)
    expect(isAssetAccount('62300001')).toBe(false)
  })
  it('líneas de factura que pueden ser un activo', () => {
    const accounts = [{ id: 'a1', account_no: '21700001', name: 'Ordenadores' }, { id: 'a2', account_no: '62300001', name: 'Servicios' }]
    const invoices = [
      { id: 'f1', invoice_type: 'purchase', document_kind: 'invoice', invoice_no: 'C-1', external_document_no: 'A-7', partner_name: 'Proveedor', invoice_date: '2026-07-01' },
      { id: 'f2', invoice_type: 'purchase', document_kind: 'invoice', invoice_no: 'C-2', partner_name: 'Proveedor', invoice_date: '2026-08-01' },
      { id: 'f3', invoice_type: 'sale', document_kind: 'invoice', invoice_no: 'F-1', partner_name: 'Cliente', invoice_date: '2027-06-30' }]
    const lines = [
      { invoice_id: 'f1', line_no: 1, amount: 1200, sign: 1, gl_account_id: 'a1' },
      { invoice_id: 'f1', line_no: 2, amount: 50, sign: 1, gl_account_id: 'a2' },
      { invoice_id: 'f2', line_no: 1, amount: 900, sign: 1, gl_account_id: 'a1' },
      { invoice_id: 'f3', line_no: 1, amount: 400, sign: 1, gl_account_id: 'a1' }]
    const alta = invoiceAssetLines(lines, accounts, invoices, 'purchase', new Set(['f2']))
    expect(alta).toHaveLength(1)
    expect(alta[0]).toMatchObject({ invoice_no: 'A-7', account_no: '21700001', amount: 1200 })
    expect(invoiceAssetLines(lines, accounts, invoices, 'sale', new Set(), '21700001')[0].amount).toBe(400)
    expect(invoiceAssetLines(lines, accounts, invoices, 'sale', new Set(), '21800001')).toEqual([])
  })
  it('clases fiscales de la cuenta, primero; y totales', () => {
    const classes = [{ code: 'MOBILIARIO', sort: 80, pgc_prefix: '216' }, { code: 'INFORMATICA', sort: 130, pgc_prefix: '217' }]
    expect(classesFor(classes, '21700001')[0].code).toBe('INFORMATICA')
    expect(assetTotals([{ status: 'active', cost: 1200, accumulated: 150, net_book_value: 1050 },
                        { status: 'disposed', cost: 18000, accumulated: 2588.89, net_book_value: 15411.11 }]))
      .toEqual({ count: 1, cost: 1200, accumulated: 150, net: 1050 })
  })
})
