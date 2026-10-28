import { describe, it, expect } from 'vitest'
import { dashPath, fmtMetric, change, zoneStatus, axis, hasData, seriesRows, textOf } from '../src/dashboards.js'

describe('tableros · formato y comparación', () => {
  it('la dirección de un tablero', () => {
    expect(dashPath('c1', 'resumen')).toBe('/empresa/c1/tableros/resumen')
  })
  it('cada unidad con su formato; sin valor, una raya', () => {
    expect(fmtMetric(121710.02, 'eur', 'es')).toBe('121.710,02 €')
    expect(fmtMetric(0.5356, 'pct', 'es')).toBe('53,6 %')
    expect(fmtMetric(4.1654, 'ratio', 'es')).toBe('4,17')
    expect(fmtMetric(4.1654, 'ratio', 'en')).toBe('4.17')
    expect(fmtMetric(null, 'eur', 'es')).toBe('—')
  })
  it('variación frente al año anterior, sin % si el anterior era 0', () => {
    expect(change(150, 100)).toEqual({ diff: 50, pct: 0.5, dir: 'up' })
    expect(change(-50, -100)).toEqual({ diff: 50, pct: 0.5, dir: 'up' })   // una pérdida menor es una subida
    expect(change(80, 100).dir).toBe('down')
    expect(change(100, 0)).toEqual({ diff: 100, pct: null, dir: 'up' })
    expect(change(100, 100).dir).toBe('same')
    expect(change(100, null)).toBeNull()
  })
  it('zona de referencia de los Ratios', () => {
    expect(zoneStatus(1.7, 1.5, 2)).toBe('ok')
    expect(zoneStatus(1.2, 1.5, 2)).toBe('low')
    expect(zoneStatus(4.17, 1.5, 2)).toBe('high')
    expect(zoneStatus(0.3, null, null)).toBeNull()
    expect(zoneStatus(null, 1, 2)).toBeNull()
    expect(zoneStatus(500, 0, null)).toBe('ok')
  })
})

describe('tableros · gráficos', () => {
  it('el eje incluye el 0 y no se lía con los meses sin datos', () => {
    const tk = axis([1200, null, 23000, -600])
    expect(tk[0]).toBeLessThanOrEqual(-600)
    expect(tk[tk.length - 1]).toBeGreaterThanOrEqual(23000)
    expect(tk).toContain(0)
  })
  it('todo a cero: eje limpio y aviso de que no hay movimientos', () => {
    expect(axis([0, 0, null])).toEqual([0, 50, 100])
    expect(hasData({ items: [{ series: [0, 0, null] }, { series: [0, null] }] })).toBe(false)
    expect(hasData({ items: [{ series: [0, 0.01] }] })).toBe(true)
    expect(hasData({ items: [{ series: null }] })).toBe(false)
  })
  it('filas mes a mes con el año anterior, para la tabla y el Excel', () => {
    const data = { months: ['2027-01-31', '2027-02-28'] }
    const w = { items: [{ code: 'CASH', series: [10, null], series_prev: [7, 8] }] }
    expect(seriesRows(data, w)).toEqual([
      { month: '2027-01-31', CASH: 10, CASH_prev: 7 },
      { month: '2027-02-28', CASH: null, CASH_prev: 8 },
    ])
    expect(seriesRows(data, { items: [{ code: 'X', series: [1, 2], series_prev: null }] })[1]).toEqual({ month: '2027-02-28', X: 2, X_prev: null })
  })
  it('los textos del catálogo en los dos idiomas', () => {
    const o = { label: 'Tesorería', label_en: 'Cash' }
    expect(textOf(o, 'label', 'es')).toBe('Tesorería')
    expect(textOf(o, 'label', 'en')).toBe('Cash')
    expect(textOf({ label: 'Solo es' }, 'label', 'en')).toBe('Solo es')
  })
})
