import { describe, it, expect } from 'vitest'
import { changePct, prevCutoff, timesBigger, COMPARE_WITH, COMP_RATIOS } from '../src/compare.js'

describe('análisis horizontal (Balance y PyG frente al año anterior)', () => {
  it('Balance: se compara con el cierre del año anterior; PyG: con el mismo periodo', () => {
    expect(prevCutoff('balance', '2026-06-30')).toBeNull()
    expect(prevCutoff('pyg', '2026-06-30')).toBe('2025-06-30')
    expect(prevCutoff('pyg', '')).toBeNull()
    expect(prevCutoff('pyg', '2028-02-29')).toBe('2027-02-28')
  })
  it('variación en %: sube, baja, sin cambio y anterior a cero', () => {
    expect(changePct(1125, 1000)).toBe('+12,5 %')
    expect(changePct(920, 1000)).toBe('−8 %')
    expect(changePct(1000, 1000)).toBe('0 %')
    expect(changePct(500, 0)).toBe('—')
  })
  it('sobre el valor absoluto: una pérdida que se reduce es una mejora (+)', () => {
    expect(changePct(-500, -1000)).toBe('+50 %')
    expect(changePct(1234.5, 1000, 'en')).toBe('+23.5 %')
  })
})

// v0.60.7 · Balance compensado (ADR 0064)
describe('Balance compensado: cuántas veces exagera', () => {
  it('la prueba ácida del vídeo 03: 3,87 sin compensar frente a 19,46 compensado', () => {
    expect(timesBigger(3.8686, 19.4636)).toBeCloseTo(5.03, 2)
  })
  it('sin dato o con cero, no se calcula', () => {
    expect(timesBigger(null, 2)).toBeNull()
    expect(timesBigger(0, 2)).toBeNull()
    expect(timesBigger(2, undefined)).toBeNull()
  })
  it('se compara con el ejercicio anterior (por defecto) o con el compensado; cuatro ratios', () => {
    expect(COMPARE_WITH).toEqual(['prev', 'comp'])
    expect(COMP_RATIOS).toEqual(['LIQ', 'QR', 'CASH', 'DEBT'])
  })
})
