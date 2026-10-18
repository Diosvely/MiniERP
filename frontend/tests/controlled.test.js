import { describe, expect, it } from 'vitest'
import { checksSummary, controlledLines, moduleScreen, ruleFor } from '../src/controlled'

// Las mismas reglas que la migración 0036
const RULES = [
  { account_prefix: '400', modules: ['invoices', 'payments'], side: 'both' },
  { account_prefix: '4009', modules: [], side: 'both' },
  { account_prefix: '410', modules: ['invoices', 'payments'], side: 'both' },
  { account_prefix: '430', modules: ['invoices', 'payments'], side: 'both' },
  { account_prefix: '472', modules: ['invoices', 'settlement'], side: 'both' },
  { account_prefix: '477', modules: ['invoices', 'settlement'], side: 'both' },
  { account_prefix: '4750', modules: ['settlement'], side: 'credit' },
  { account_prefix: '4700', modules: ['settlement'], side: 'debit' },
]

describe('cuentas controladas', () => {
  it('gana el prefijo más largo', () => {
    expect(ruleFor('40090001', RULES).modules).toEqual([])
    expect(ruleFor('40000001', RULES).account_prefix).toBe('400')
    expect(ruleFor('57200001', RULES)).toBeNull()
  })
  it('detecta las líneas controladas, por su lado', () => {
    const hits = controlledLines([
      { account_no: '62300001', debit: 100, credit: 0 },
      { account_no: '41000001', debit: 0, credit: 100 },
      { account_no: '47500001', debit: 50, credit: 0 },    // pagar a Hacienda (Debe): libre
      { account_no: '47500001', debit: 0, credit: 50 },    // la 4750 al Haber: solo la liquidación
      { account_no: '40090001', debit: 0, credit: 10 },    // 4009: libre
    ], RULES)
    expect(hits.map((h) => [h.line, h.account_no])).toEqual([[2, '41000001'], [4, '47500001']])
  })
  it('importes en texto (como en el formulario) y líneas sin importe', () => {
    expect(controlledLines([{ account_no: '47000001', debit: '', credit: '12,5' }], RULES)).toEqual([])
    expect(controlledLines([{ account_no: '47000001', debit: '12.5', credit: '' }], RULES)).toHaveLength(1)
  })
  it('lleva a la pantalla del módulo', () => {
    expect(moduleScreen(['invoices', 'payments'])).toBe('payments')
    expect(moduleScreen('invoices, settlement')).toBe('invoices')
    expect(moduleScreen(['settlement'])).toBe('settlement')
    expect(moduleScreen([])).toBe('journal')
    expect(moduleScreen(['assets'])).toBe('assets')
    expect(moduleScreen('accruals')).toBe('adjustments')
    expect(moduleScreen(['impairments'])).toBe('adjustments')
  })
  it('resume las comprobaciones', () => {
    expect(checksSummary([{ status: 'ok' }, { status: 'ok' }, { status: 'warning' }, { status: 'error' }]))
      .toEqual({ ok: 2, info: 0, warning: 1, error: 1 })
  })
})
