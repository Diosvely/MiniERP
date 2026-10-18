import { describe, expect, it } from 'vitest'
import { activeIn, monthEnd, nextMonth, nextPayment, payMonths, payrollEntryLines, payrollTotals, payslipSummary, ssBase } from '../src/payroll'

// Las cifras del supuesto de referencia de la base de datos (fase 44, Oficina Guanche SL, tipos de 2026)
const LIM = { year: 2026, max_base: 5101.2, min_base: 1424.4 }
const ANA_ENE = { salary: 2000, extra_accrual: 333.33, extra_paid: 0, ss_base: 2333.33, ss_employee: 151.67, ss_employer: 738.5, irpf_pct: 12, irpf: 240, net: 1608.33 }
const LUIS = { salary: 1750, extra_accrual: 0, extra_paid: 0, ss_base: 1750, ss_employee: 114.63, ss_employer: 574.88, irpf_pct: 2, irpf: 35, net: 1600.37 }
const ANA_JUN = { ...ANA_ENE, extra_accrual: 333.35, extra_paid: 2000, irpf: 480, net: 3368.33 }
const txt = (lines) => lines.map((l) => `${l.account_no} ${l.debit ? 'D ' + l.debit : 'H ' + l.credit}`).join(' | ')

describe('nóminas · base de cotización (art. 147 LGSS)', () => {
  it('salario + prorrata de las pagas extra: Ana 2.000 + 333,33 = 2.333,33; Luis 1.500 + 250 = 1.750', () => {
    expect(ssBase({ monthly_salary: '2000', extra_payments: 2 }, LIM)).toEqual({ prorata: 333.33, remuneration: 2333.33, base: 2333.33, capped: false, belowMin: false })
    expect(ssBase({ monthly_salary: '1500', extra_payments: '2' }, LIM).base).toBe(1750)
  })
  it('tope de la base máxima y aviso de la mínima', () => {
    expect(ssBase({ monthly_salary: '6000', extra_payments: 2 }, LIM)).toMatchObject({ remuneration: 7000, base: 5101.2, capped: true })
    expect(ssBase({ monthly_salary: '1000', extra_payments: 2 }, LIM)).toMatchObject({ base: 1166.67, belowMin: true })
    expect(ssBase({ monthly_salary: '1.000,5', extra_payments: 0 }, null).base).toBe(0)
  })
  it('meses de las pagas extra y meses de alta', () => {
    expect([payMonths(2), payMonths(3), payMonths('4'), payMonths(0)]).toEqual([[6, 12], [4, 8, 12], [3, 6, 9, 12], []])
    expect([monthEnd('2026-02'), monthEnd('2028-02-10'), nextMonth('2026-12-31'), nextMonth('2026-01-31')]).toEqual(['2026-02-28', '2028-02-29', '2027-01', '2026-02'])
    const luis = { hire_date: '2026-01-01', end_date: '2026-12-15' }
    expect([activeIn(luis, '2025-12'), activeIn(luis, '2026-12'), activeIn({ hire_date: '2026-12-01' }, '2026-11')]).toEqual([false, true, false])
  })
})

describe('nóminas · asiento (supuesto de la fase 44)', () => {
  it('enero: 640 4.083,33 · 642 1.313,38 / 476 1.579,68 · 4751 275 · 465 3.542,03 (líquidos + paga devengada)', () => {
    expect(txt(payrollEntryLines([ANA_ENE, LUIS])))
      .toBe('64000001 D 4083.33 | 64200001 D 1313.38 | 47600001 H 1579.68 | 47510001 H 275 | 46500001 H 3542.03')
    expect(payrollTotals([ANA_ENE, LUIS])).toEqual({ gross: 3750, expense: 5396.71, ssEmployee: 266.3, ssEmployer: 1313.38, irpf: 275, net: 3208.7 })
  })
  it('junio: la paga extra se paga (465 al Debe) y cuadra el asiento', () => {
    const lines = payrollEntryLines([ANA_JUN], 9)
    expect(txt(lines)).toBe('640000001 D 2333.35 | 465000001 D 2000 | 642000001 D 738.5 | 476000001 H 890.17 | 475100001 H 480 | 465000001 H 3701.68')
    const sum = (k) => Math.round(lines.reduce((s, l) => s + l[k] * 100, 0)) / 100
    expect(sum('debit')).toBe(sum('credit'))
  })
  it('recibo de salarios: devengos, deducciones del trabajador y coste para la empresa', () => {
    const p = payslipSummary({ ...ANA_JUN, ss_detail: [
      { concept: 'common', name: 'Contingencias comunes', base: 2333.33, employer_pct: 23.6, employee_pct: 4.7, employer: 550.67, employee: 109.67 },
      { concept: 'fogasa', name: 'FOGASA', base: 2333.33, employer_pct: 0.2, employee_pct: 0, employer: 4.67, employee: 0 }] })
    expect(p.earnings).toBe(4000)
    expect(p.deductions.map((d) => d.concept)).toEqual(['common'])
    expect(p.employer.map((d) => d.amount)).toEqual([550.67, 4.67])
    expect(p.totalDeductions).toBe(631.67)
    expect(p.cost).toBe(3071.85)
  })
  it('siguiente paso: primero el líquido, después los seguros sociales', () => {
    expect([nextPayment({ status: 'posted' }), nextPayment({ status: 'posted', net_payment_entry_no: 3 }),
            nextPayment({ status: 'posted', net_payment_entry_no: 3, ss_payment_entry_no: 4 }), nextPayment({ status: 'cancelled' })])
      .toEqual(['net', 'social_security', null, null])
  })
})
