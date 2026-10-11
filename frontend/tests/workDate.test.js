import { describe, it, expect } from 'vitest'
import { computeWorkDate, todayIso, workYear, workQuarter, workMonthStart, workDate } from '../src/workDate.js'

const y = (year, status = 'open') => ({ starting_date: `${year}-01-01`, ending_date: `${year}-12-31`, status })

describe('fecha de trabajo de la empresa (Work Date de Business Central)', () => {
  it('empresa al día (ejercicio abierto que incluye hoy) → hoy', () => {
    expect(computeWorkDate({ today: '2026-02-14', years: [y(2025, 'closed'), y(2026)], lastPosted: '2026-02-10' })).toBe('2026-02-14')
  })
  it('empresa importada de 2019 a 2024 → fecha del último asiento', () => {
    const years = [2019, 2020, 2021, 2022, 2023, 2024].map((n) => y(n, n < 2024 ? 'closed' : 'open'))
    expect(computeWorkDate({ today: '2026-10-11', years, lastPosted: '2024-12-31' })).toBe('2024-12-31')
  })
  it('el ejercicio de hoy existe pero está cerrado → último asiento', () => {
    expect(computeWorkDate({ today: '2026-10-11', years: [y(2026, 'closed')], lastPosted: '2026-09-30' })).toBe('2026-09-30')
  })
  it('empresa nueva sin asientos → hoy', () => {
    expect(computeWorkDate({ today: '2026-10-11', years: [], lastPosted: null })).toBe('2026-10-11')
  })
  it('año, trimestre y primer día del mes salen de la fecha de trabajo', () => {
    const c = { work_date: '2024-11-30' }
    expect(workYear(c)).toBe(2024)
    expect(workQuarter(c)).toBe(4)
    expect(workMonthStart(c)).toBe('2024-11-01')
    expect(workQuarter({ work_date: '2026-02-01' })).toBe(1)
    expect(workQuarter({ work_date: '2026-07-01' })).toBe(3)
  })
  it('sin fecha de trabajo (pantalla suelta) → hoy', () => {
    expect(workDate({})).toBe(todayIso())
  })
  it('hoy en hora local, no en UTC (00:30 del 1 de enero sigue siendo 1 de enero)', () => {
    expect(todayIso(new Date(2026, 0, 1, 0, 30))).toBe('2026-01-01')
  })
})
