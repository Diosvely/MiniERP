import { describe, it, expect } from 'vitest'
import { reportBase, daysIn, monthEnd, monthOf, moveToYear, monthNames, simTitle, simBanner } from '../src/reportPeriod.js'
import es from '../src/i18n/es.js'

const t = (k) => k.split('.').reduce((o, p) => o?.[p], es)

describe('mes rápido · el «hasta» de cada mes', () => {
  it('último día del mes, con los bisiestos', () => {
    expect(monthEnd(2026, 1)).toBe('2026-01-31')
    expect(monthEnd(2026, 2)).toBe('2026-02-28')
    expect(monthEnd(2028, 2)).toBe('2028-02-29')
    expect(monthEnd(2026, 4)).toBe('2026-04-30')
    expect(monthEnd('2026', '12')).toBe('2026-12-31')
    expect(daysIn(2100, 2)).toBe(28)
  })
  it('marca el mes de la fecha escrita a mano, solo si es del ejercicio elegido', () => {
    expect(monthOf('2026-03-15', 2026)).toBe(3)
    expect(monthOf('2026-03-15', '2026')).toBe(3)
    expect(monthOf('2025-03-15', 2026)).toBeNull()
    expect(monthOf('', 2026)).toBeNull()
    expect(monthOf(null, 2026)).toBeNull()
  })
  it('al cambiar de ejercicio, el «hasta» va al mismo mes del nuevo', () => {
    expect(moveToYear('2027-02-28', 2028)).toBe('2028-02-29')   // fin de mes → fin de mes
    expect(moveToYear('2028-02-29', 2027)).toBe('2027-02-28')
    expect(moveToYear('2026-06-30', 2025)).toBe('2025-06-30')
    expect(moveToYear('2026-03-15', 2027)).toBe('2027-03-15')
    expect(moveToYear('', 2027)).toBe('')                      // «Todo» sigue siendo todo
  })
  it('«2» o «0102» se leen en el ejercicio elegido', () => {
    expect(reportBase('2026-03-31', 2026, '2026-10-28')).toBe('2026-03-31')
    expect(reportBase('', 2026, '2026-10-28')).toBe('2026-10-28')
    expect(reportBase('', 2025, '2026-10-28')).toBe('2025-12-31')
  })
  it('los 12 meses con nombre corto en los dos idiomas', () => {
    const es12 = monthNames('es'); const en12 = monthNames('en')
    expect(es12).toHaveLength(12); expect(en12).toHaveLength(12)
    expect(es12[0].toLowerCase()).toBe('ene'); expect(es12[11].toLowerCase()).toBe('dic')
    expect(en12[0]).toBe('Jan'); expect(en12[11]).toBe('Dec')
    for (const s of [...es12, ...en12]) expect(s).toMatch(/^[A-ZÁÉÍÓÚ][a-záéíóú]{2}$/)
  })
})

describe('simulación con los asientos en edición', () => {
  it('el Excel y la impresión llevan SIMULACIÓN en el título', () => {
    expect(simTitle('Balance de situación', true, t('sim.prefix'))).toBe('SIMULACIÓN · Balance de situación')
    expect(simTitle('Balance de situación', false, t('sim.prefix'))).toBe('Balance de situación')
  })
  it('la franja dice cuántos asientos en edición entran', () => {
    expect(simBanner(null, t)).toBe(t('sim.loading'))
    expect(simBanner(0, t)).toBe(t('sim.none'))
    expect(simBanner(1, t)).toContain('1 asiento en edición')
    expect(simBanner(3, t)).toContain('3 asientos en edición')
  })
})
