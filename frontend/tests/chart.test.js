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

import { waterfall } from '../src/chart.js'
describe('waterfall · cascada del EFE', () => {
  it('de 1.000 iniciales, +500 explotación, −300 inversión, −100 financiación → 1.100 finales', () => {
    const b = waterfall(1000, [{ key: 'A', value: 500 }, { key: 'B', value: -300 }, { key: 'C', value: -100 }])
    expect(b.map((x) => [x.key, x.from, x.to, x.kind])).toEqual([
      ['start', 0, 1000, 'total'], ['A', 1000, 1500, 'up'], ['B', 1500, 1200, 'down'], ['C', 1200, 1100, 'down'], ['end', 0, 1100, 'total']])
  })
  it('con descubierto: el saldo inicial negativo empieza bajo el cero', () => {
    const b = waterfall(-200, [{ key: 'A', value: 300 }])
    expect(b[0]).toMatchObject({ from: 0, to: -200 })
    expect(b.at(-1)).toMatchObject({ from: 0, to: 100 })
  })
})
