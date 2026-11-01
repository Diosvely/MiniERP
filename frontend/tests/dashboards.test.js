import { describe, it, expect } from 'vitest'
import es from '../src/i18n/es.js'
import en from '../src/i18n/en.js'
import { dashPath, fmtMetric, change, zoneStatus, axis, hasData, seriesRows, textOf, periods, periodLabel, taxName, tableLink, hasZones, rankingRows, checkDetail, CHECK_ICON } from '../src/dashboards.js'

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
  it('los periodos medios, en días enteros (v0.54.0)', () => {
    expect(fmtMetric(65.0917, 'days', 'es')).toBe('65 días')
    expect(fmtMetric(158.3311, 'days', 'en')).toBe('158 days')
    expect(fmtMetric(1.2, 'days', 'es')).toBe('1 día')
    expect(fmtMetric(1500, 'days', 'es')).toBe('1500 días')   // en español, sin punto hasta 5 cifras
    expect(fmtMetric(null, 'days', 'es')).toBe('—')
  })
  it('cada enlace del catálogo tiene su texto en los dos idiomas (v0.54.0)', () => {
    for (const link of ['pyg', 'balance', 'ratios', 'payments', 'cashflow', 'settlement', 'withholdings']) {
      expect(es.dash.link[link]).toBeTruthy()
      expect(en.dash.link[link]).toBeTruthy()
    }
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
  it('márgenes en %: marcas redondas en % que abarcan los valores (v0.53.0)', () => {
    const tk = axis([0.6917, 0.7, null, 0.5356], 'pct')
    expect(tk[0]).toBe(0)
    expect(tk[tk.length - 1]).toBeGreaterThanOrEqual(0.7)
    expect(tk[tk.length - 1]).toBeLessThanOrEqual(1)   // en %, no en unidades
    expect(tk.length).toBeGreaterThan(2)   // antes: [0, 50, 100] y los márgenes aplastados contra el cero
    expect(tk.every((v) => Number.isInteger(Math.round(v * 1e6) / 1e4))).toBe(true)
    const neg = axis([-0.12, 0.08], 'pct')
    expect(neg[0]).toBeLessThanOrEqual(-0.12)
    expect(neg).toContain(0)
    expect(axis([0, 0], 'pct')).toEqual([0, 0.5, 1])
  })
  it('todo a cero: eje limpio y aviso de que no hay movimientos', () => {
    expect(axis([0, 0, null])).toEqual([0, 50, 100])
    expect(hasData({ items: [{ series: [0, 0, null] }, { series: [0, null] }] })).toBe(false)
    expect(hasData({ items: [{ series: [0, 0.01] }] })).toBe(true)
    expect(hasData({ items: [{ series: null }] })).toBe(false)
  })
  it('barras por trimestre: 1T a 4T, en la tabla y el Excel (v0.55.0)', () => {
    const data = { months: ['2026-01-31', '2026-02-28', '2026-03-31'] }
    const w = { mode: 'quarter', items: [{ code: 'TAX_RES', series: [938, 308, null, null], series_prev: [1, 2, 3, 4] }] }
    expect(periods(data, w)).toEqual([1, 2, 3, 4])
    expect(periods(data, { mode: 'month' })).toEqual(data.months)
    const rows = seriesRows(data, w)
    expect(rows).toHaveLength(4)
    expect(rows[1]).toMatchObject({ period: 2, quarter: 2, month: null, TAX_RES: 308, TAX_RES_prev: 2 })
    expect(rows[2].TAX_RES).toBeNull()
    expect(periodLabel(1, 'es', [])).toBe('1T')
    expect(periodLabel(4, 'en', [])).toBe('Q4')
    expect(periodLabel('2026-02-28', 'es', ['Ene', 'Feb'])).toBe('Feb')
  })
  it('la tabla enlaza a la pantalla de sus métricas y enseña la zona solo si la hay (v0.55.0)', () => {
    expect(tableLink([{ link: 'pyg' }, { link: 'ratios' }])).toBe('ratios')
    expect(tableLink([{ link: 'settlement' }, { link: 'withholdings' }])).toBe('settlement')
    expect(tableLink([{}])).toBe('ratios')
    expect(hasZones([{ ref_min: null, ref_max: null }])).toBe(false)
    expect(hasZones([{ ref_min: null, ref_max: 60 }])).toBe(true)
  })
  it('ranking: los primeros, el resto y lo que no tiene tercero, con su % (v0.56.0)', () => {
    const lab = { rest: (n) => `Resto (${n})`, none: 'Sin cliente' }
    const r = {
      source: 'customers', base: 'total',
      rows: [{ key: '43000001', label: 'Cliente General SL', value: 118000, prev: 90000 }],
      rest: { count: 1, value: 2000, prev: 1000 }, none: { value: 0, prev: 0 },
      total: { value: 120000, prev: 91000 }, sales: { value: 120000, prev: 91000 },
    }
    const rows = rankingRows(r, lab)
    expect(rows.map((x) => x.kind)).toEqual(['row', 'rest'])   // sin «Sin cliente»: no hay importe
    expect(rows[0].share).toBeCloseTo(118000 / 120000)
    expect(rows[1]).toMatchObject({ label: 'Resto (1)', value: 2000, prev: 1000 })
    const g = rankingRows({ ...r, source: 'expense_groups', base: 'sales', rest: { count: 0 }, none: { value: 50, prev: null },
      total: { value: 60000 }, sales: { value: 120000 } }, lab)
    expect(g.map((x) => x.kind)).toEqual(['row', 'none'])
    expect(g[0].share).toBeCloseTo(118000 / 120000)          // gastos: sobre las ventas
    expect(rankingRows({ ...r, total: { value: 0 } }, lab)[0].share).toBeNull()
    expect(rankingRows(null, lab)).toEqual([])
  })
  it('los textos del ranking en los dos idiomas (v0.56.0)', () => {
    for (const lang of [es, en]) {
      for (const src of ['customers', 'suppliers', 'expense_groups']) expect(lang.dash.rank.none[src]).toBeTruthy()
      expect(lang.dash.rank.rest).toContain('{n}')
      expect(lang.dash.rank.top).toContain('{p}')
    }
  })
  it('lista de control: icono y texto de cada gravedad, y la cifra de cada fila (v0.57.0)', () => {
    const t = (k) => k.split('.').reduce((o, x) => o?.[x], es) ?? k
    for (const sev of ['ok', 'info', 'warning', 'error', 'na']) {
      expect(CHECK_ICON[sev]).toBeTruthy()
      expect(es.dash.check[sev]).toBeTruthy()
      expect(en.dash.check[sev]).toBeTruthy()
    }
    for (const link of ['checks', 'entries', 'settlement', 'payments']) {
      expect(es.dash.check.go[link]).toBeTruthy()
      expect(en.dash.check.go[link]).toBeTruthy()
    }
    expect(checkDetail({ code: 'anomalies', unit: 'count', value: 3, extra: 1, severity: 'error' }, 'es', t)).toBe('3 (1 imposibles)')
    expect(checkDetail({ code: 'anomalies', unit: 'count', value: 2, extra: 0, severity: 'warning' }, 'es', t)).toBe('2')
    expect(checkDetail({ code: 'overdue_in', unit: 'eur', value: 23540, extra: 2140, severity: 'error' }, 'es', t))
      .toBe('23.540,00 € (2.140,00 € a más de 90 días)')
    expect(checkDetail({ code: 'settlements', unit: 'count', value: 1, extra: null, severity: 'error' }, 'es', t)).toBe('1')
    expect(checkDetail({ code: 'overdue_in', unit: 'eur', value: null, severity: 'na' }, 'es', t)).toBe('no aplica')
  })
  it('ranking sin %: las cuentas con saldo al revés, con su nota (v0.57.0)', () => {
    const r = { source: 'anomalies', base: 'none', rows: [{ key: '11300001', label: 'Reservas voluntarias', value: 850, note: 'Saldo acreedor.' }],
      rest: { count: 0 }, none: { value: 0 }, total: { value: 850 }, sales: { value: 120000 } }
    const rows = rankingRows(r, { rest: () => '', none: '' })
    expect(rows).toHaveLength(1)
    expect(rows[0].share).toBeNull()
    expect(rows[0].note).toBe('Saldo acreedor.')
    for (const lang of [es, en]) for (const src of ['anomalies', 'overdue_customers']) expect(lang.dash.rank.none[src]).toBeTruthy()
  })
  it('el impuesto de la empresa en cada idioma (v0.55.0)', () => {
    expect(taxName('VAT', 'es')).toBe('IVA')
    expect(taxName('VAT', 'en')).toBe('VAT')
    expect(taxName('IGIC', 'es')).toBe('IGIC')
    expect(es.dash.taxType).toContain('{t}')
    expect(en.dash.taxType).toContain('{t}')
  })
  it('filas mes a mes con el año anterior, para la tabla y el Excel', () => {
    const data = { months: ['2027-01-31', '2027-02-28'] }
    const w = { items: [{ code: 'CASH', series: [10, null], series_prev: [7, 8] }] }
    expect(seriesRows(data, w)).toEqual([
      { period: '2027-01-31', month: '2027-01-31', quarter: null, CASH: 10, CASH_prev: 7 },
      { period: '2027-02-28', month: '2027-02-28', quarter: null, CASH: null, CASH_prev: 8 },
    ])
    expect(seriesRows(data, { items: [{ code: 'X', series: [1, 2], series_prev: null }] })[1]).toEqual({ period: '2027-02-28', month: '2027-02-28', quarter: null, X: 2, X_prev: null })
  })
  it('los textos del catálogo en los dos idiomas', () => {
    const o = { label: 'Tesorería', label_en: 'Cash' }
    expect(textOf(o, 'label', 'es')).toBe('Tesorería')
    expect(textOf(o, 'label', 'en')).toBe('Cash')
    expect(textOf({ label: 'Solo es' }, 'label', 'en')).toBe('Solo es')
  })
})
