import { describe, expect, it } from 'vitest'
import { assetShare, balanced, concessionEntry, emptyForm, imputationEntry, partA, partB, paren, payload, shortTerm, unconditionalEntry, undoable } from '../src/grants'
import es from '../src/i18n/es.js'
import en from '../src/i18n/en.js'

const lines = (ls) => ls.map((l) => `${l.account} ${l.debit ? 'D ' + l.debit : 'H ' + l.credit}`).join(' | ')

// Las cifras son las de los supuestos de referencia (docs del proyecto: supuestos-v0.44.0.md; base de datos: fases 59 y 60)
describe('subvenciones · asientos que se ven antes de contabilizar', () => {
  it('S1 · concesión de capital no reintegrable, con su efecto impositivo', () => {
    const e = concessionEntry({ ...emptyForm('2026-03-15'), amount: '20.000' })
    expect(lines(e)).toBe('4708 D 20000 | 940 H 20000 | 8301 D 5000 | 479 H 5000')
    expect(balanced(e)).toBe(true)
  })
  it('S1 · imputación del año (10 %) y S1b · lo que queda al vender', () => {
    expect(lines(imputationEntry(2000, 500))).toBe('840 D 2000 | 746 H 2000 | 479 D 500 | 8301 H 500')
    expect(lines(imputationEntry(14000, 3500))).toBe('840 D 14000 | 746 H 14000 | 479 D 3500 | 8301 H 3500')
  })
  it('S2 · a la explotación: directa a resultados, con su propia 4708', () => {
    expect(lines(concessionEntry({ ...emptyForm('2026-05-15'), kind: 'operating', amount: '3000' }))).toBe('47089 D 3000 | 740 H 3000')
  })
  it('S3 · reintegrable cobrada (522) y cuando deja de serlo', () => {
    const f = { ...emptyForm('2026-09-01'), amount: '10000', refundable: true, condition_due: '2027-03-31', collected: true }
    expect(lines(concessionEntry(f))).toBe('572 D 10000 | 522 H 10000')
    expect(lines(concessionEntry({ ...f, condition_due: '2028-06-30' }))).toBe('572 D 10000 | 172 H 10000')
    expect(lines(unconditionalEntry({ kind: 'capital', amount: 10000, tax_rate: 25, grant_date: '2026-09-01', condition_due: '2027-03-31' })))
      .toBe('522 D 10000 | 940 H 10000 | 8301 D 2500 | 479 H 2500')
  })
  it('la subvención financia el 40 % de la máquina', () => {
    expect([assetShare('20.000', 50000), assetShare('', 50000), assetShare('100', 0)]).toEqual([40, 0, 0])
  })
  it('a corto si la condición vence en 12 meses', () => {
    expect([shortTerm('2026-09-01', '2027-09-01'), shortTerm('2026-09-01', '2027-09-02')]).toEqual([true, false])
  })
  it('sin importe, sin asiento; deshacer el último', () => {
    expect(concessionEntry(emptyForm('2026-01-01'))).toEqual([])
    expect(undoable([{ id: 'a', seq: 1, status: 'posted' }, { id: 'b', seq: 2, status: 'posted' }, { id: 'c', seq: 3, status: 'cancelled' }])).toBe('b')
  })
  it('lo que se manda a la base de datos', () => {
    const f = { ...emptyForm('2026-03-15'), description: ' Máquina ', grantor: 'Gobierno de Canarias', amount: '20.000', asset_id: 'fa1' }
    expect(payload(f, 'c')).toEqual({ company_id: 'c', kind: 'capital', date: '2026-03-15', refundable: false, collected: false,
      description: 'Máquina', grantor: 'Gobierno de Canarias', amount: 20000, tax_rate: 25, asset_id: 'fa1' })
    expect(payload({ ...f, kind: 'operating' }, 'c').asset_id).toBeUndefined()
  })
})

describe('ECPN · supuesto S4', () => {
  const data = {
    part_a: { result: 30000, b_grants: 20000, b_tax: -5000, b_other: 0, b_total: 15000, c_grants: -2000, c_tax: 500, c_total: -1500, total: 43500 },
    part_b: { start: { capital: 60000, reserves: 10000, result: 8000 }, other: { reserves: 8000, result: -8000 }, owners: { result: 0 },
      recognised: { result: 30000, grants: 13500 } },
    columns: ['capital', 'reserves', 'result', 'grants'], start: 78000, end: 121500, balance_net_worth: 121500, ok: true,
  }
  it('parte A: 30.000 + 15.000 − 1.500 = 43.500', () => {
    expect(partA(data.part_a).map((r) => `${r.key}:${r.amount}`).join(' '))
      .toBe('result:30000 b_grants:20000 b_tax:-5000 b_total:15000 c_grants:-2000 c_tax:500 c_total:-1500 total:43500')
  })
  it('parte B: 78.000 → 121.500 por columnas', () => {
    const { cols, rows } = partB(data)
    expect(cols).toEqual(['capital', 'reserves', 'result', 'grants'])
    expect(rows.map((r) => `${r.key}:${r.total}`).join(' ')).toBe('start:78000 recognised:43500 owners:0 other:0 end:121500')
    expect(rows.at(-1).values).toEqual({ capital: 60000, reserves: 18000, result: 30000, grants: 13500 })
  })
  it('las cifras negativas, entre paréntesis', () => {
    expect([paren(-1500, String), paren(500, String)]).toEqual(['(1500)', '500'])
  })
})

describe('subvenciones y ECPN · textos', () => {
  const keys = (o, p = '') => Object.entries(o).flatMap(([k, v]) => (v && typeof v === 'object' ? keys(v, `${p}${k}.`) : [`${p}${k}`])).sort()
  it('es y en tienen los mismos textos', () => {
    expect(keys(en.gr)).toEqual(keys(es.gr))
    expect(keys(en.ecpn)).toEqual(keys(es.ecpn))
    expect([es.nav.grants.label, es.nav.ecpn.label]).toEqual(['Subvenciones', 'Cambios en el patrimonio neto'])
  })
  it('cada cuenta del asiento y cada fila y columna del ECPN tienen su nombre', () => {
    for (const k of ['4708', '47089', '940', '740', '522', '172', '8301', '479', '840', '746', '572']) expect(es.gr.account[k], k).toBeTruthy()
    for (const k of ['result', 'b_grants', 'b_tax', 'b_other', 'b_total', 'c_grants', 'c_tax', 'c_total', 'total']) expect(es.ecpn.a[k], k).toBeTruthy()
    for (const k of ['start', 'recognised', 'owners', 'other', 'end']) expect(es.ecpn.row[k], k).toBeTruthy()
    for (const k of ['capital', 'premium', 'reserves', 'prior_results', 'result', 'interim', 'grants']) expect(es.ecpn.col[k], k).toBeTruthy()
  })
})
