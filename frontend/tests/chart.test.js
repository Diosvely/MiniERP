import { describe, it, expect } from 'vitest'
import { niceTicks } from '../src/chart.js'

describe('niceTicks · marcas redondas del eje del gráfico', () => {
  it('de 0 a 49.980 → 0 · 25.000 · 50.000 (pocas marcas, redondas, que cubren el rango)', () => {
    expect(niceTicks(0, 49980.12)).toEqual([0, 25000, 50000])
  })
  it('de 30.000 a 50.000 → de 10.000 en 10.000', () => {
    expect(niceTicks(30000, 50000)).toEqual([30000, 40000, 50000])
  })
  it('con saldos negativos (descubierto) el eje baja de cero', () => {
    const t = niceTicks(-1200, 3500)
    expect(t[0]).toBeLessThan(0)
    expect(t.at(-1)).toBeGreaterThanOrEqual(3500)
  })
  it('todo a cero no rompe (rango mínimo de 1)', () => {
    expect(niceTicks(0, 0).length).toBeGreaterThanOrEqual(2)
  })
})
