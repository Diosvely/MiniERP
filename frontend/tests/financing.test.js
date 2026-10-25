import { describe, expect, it } from 'vitest'
import { accountKey, accounts, balanced, defaultTax, emptyForm, instalmentEntry, paidCount, parseRate, payload, ready, startEntry, undoable } from '../src/financing'
import es from '../src/i18n/es.js'
import en from '../src/i18n/en.js'

const lines = (ls) => ls.map((l) => `${l.account} ${l.debit ? 'D ' + l.debit : 'H ' + l.credit}`).join(' | ')

// Las cifras son las de los supuestos de referencia (docs del proyecto: supuestos-v0.43.0.md; base de datos: fases 57 y 58)
describe('financiación · asientos que se ven antes de contabilizar', () => {
  it('F1 · alta del préstamo: lo que baja la deuda en 12 meses, a corto', () => {
    const calc = { kind: 'loan', net_amount: 100000, short_part: 17739.64 }
    expect(lines(startEntry(calc))).toBe('572 D 100000 | 5200 H 17739.64 | 1700 H 82260.36')
    expect(lines(startEntry(calc, 'other'))).toBe('572 D 100000 | 5210 H 17739.64 | 1710 H 82260.36')
    expect(balanced(startEntry(calc))).toBe(true)
  })
  it('F2 · con comisión: la deuda, por lo recibido (99.000)', () => {
    expect(lines(startEntry({ kind: 'loan', net_amount: 99000, short_part: 17432.81 }))).toBe('572 D 99000 | 5200 H 17432.81 | 1700 H 81567.19')
  })
  it('F3 · alta del leasing: el activo, sin IVA / IGIC', () => {
    expect(lines(startEntry({ kind: 'leasing', net_amount: 50000, short_part: 11030.59 }))).toBe('213 D 50000 | 5240 H 11030.59 | 1740 H 38969.41')
  })
  it('F1b · la cuota que salda los intereses devengados (527)', () => {
    const next = { kind: 'loan', payment: 23739.64, accrued_used: 2956.3, interest_expense: 3043.7, short_part: 17739.64, long_part: 0,
      accrued_account_no: '52700001', interest_account_no: '66230001', short_account_no: '52000001', long_account_no: '17000001' }
    const e = instalmentEntry(next)
    expect(lines(e)).toBe('52700001 D 2956.3 | 66230001 D 3043.7 | 52000001 D 17739.64 | 572 H 23739.64')
    expect(balanced(e)).toBe(true)
  })
  it('F3 · la factura de la cuota del leasing, con el IGIC sobre la cuota entera', () => {
    const next = { kind: 'leasing', payment: 13500, accrued_used: 0, interest_expense: 2469.41, short_part: 11030.59, long_part: 0,
      accrued_account_no: '52700001', interest_account_no: '66230001', short_account_no: '52400001', long_account_no: '17400001' }
    const e = instalmentEntry(next, 7)
    expect(lines(e)).toBe('52400001 D 11030.59 | 66230001 D 2469.41 | 472 D 945 | 410 H 14445')
    expect(balanced(e)).toBe(true)
  })
  it('sin cálculo, sin asientos', () => {
    expect(startEntry(null)).toEqual([])
    expect(instalmentEntry(null)).toEqual([])
  })
})

describe('financiación · formulario', () => {
  it('lo que se manda a la base de datos (préstamo y leasing)', () => {
    const f = { ...emptyForm('loan', '2026-01-01'), description: ' Préstamo ', principal: '100.000', rate: '6', periods: '5', frequency: '1', costs: '1.000' }
    expect(payload(f, 'c')).toEqual({ company_id: 'c', kind: 'loan', frequency: 1, start_date: '2026-01-01', description: 'Préstamo',
      lender_type: 'bank', periods: 5, rate: 6, principal: 100000, costs: 1000 })
    const g = { ...emptyForm('leasing', '2026-01-01'), description: 'Máquina', fair_value: '50.000', instalment: '13.500', purchase_option: '2.500', periods: '4', frequency: '1', useful_years: '10' }
    expect(payload(g, 'c')).toEqual({ company_id: 'c', kind: 'leasing', frequency: 1, start_date: '2026-01-01', description: 'Máquina',
      periods: 4, fair_value: 50000, instalment: 13500, purchase_option: 2500, useful_life_months: 120 })
  })
  it('el tipo admite cuatro decimales', () => {
    expect([parseRate('4,375'), parseRate('6 %'), parseRate(''), parseRate('x')]).toEqual([4.375, 6, undefined, undefined])
  })
  it('lo mínimo para calcular', () => {
    expect(ready({ ...emptyForm('loan', '2026-01-01'), principal: '1000', periods: '12' })).toBe(true)
    expect(ready({ ...emptyForm('loan', '2026-01-01'), principal: '', periods: '12' })).toBe(false)
    expect(ready({ ...emptyForm('leasing', '2026-01-01'), fair_value: '50000', periods: '4' })).toBe(false)
  })
  it('el nombre de cada cuenta del asiento, por su prefijo', () => {
    expect([accountKey('52400001'), accountKey('66230001'), accountKey('4721'), accountKey('21300001'), accountKey('600')]).toEqual(['5240', '6623', '472', '213', null])
    for (const k of ['1700', '1710', '1740', '5200', '5210', '5240', '6623', '6624', '527', '528', '213', '472', '410', '572']) expect(es.fin.account[k], k).toBeTruthy()
  })
  it('cuentas por defecto', () => {
    expect(accounts('leasing').asset).toBe('213')
    expect(accounts('loan', 'other').accrued).toBe('528')
  })
  it('se deshace el último movimiento; las cuotas pagadas', () => {
    const ev = [{ id: 'a', seq: 1, kind: 'start', status: 'posted' }, { id: 'b', seq: 2, kind: 'payment', status: 'posted' }, { id: 'c', seq: 3, kind: 'payment', status: 'cancelled' }]
    expect(undoable(ev)).toBe('b')
    expect(paidCount(ev)).toBe(1)
    expect(undoable([])).toBeNull()
  })
  it('el impuesto de la cuota: el general (IGIC 7 % en Canarias)', () => {
    expect(defaultTax([{ tax_code: 'IGIC0', rate_pct: 0 }, { tax_code: 'IGIC7', rate_pct: 7 }, { tax_code: 'IGIC15', rate_pct: 15 }])).toBe('IGIC7')
    expect(defaultTax([{ tax_code: 'VAT21_ISP', rate_pct: 21, rate_category: 'reverse_charge' }, { tax_code: 'VAT21', rate_pct: 21 }])).toBe('VAT21')
  })
})

describe('financiación · textos', () => {
  it('es y en tienen los mismos textos de la pantalla', () => {
    const keys = (o, p = '') => Object.entries(o).flatMap(([k, v]) => (v && typeof v === 'object' ? keys(v, `${p}${k}.`) : [`${p}${k}`])).sort()
    expect(keys(en.fin)).toEqual(keys(es.fin))
    expect(es.nav.financing.label).toBe('Financiación')
  })
})
