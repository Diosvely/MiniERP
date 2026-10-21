import { describe, expect, it } from 'vitest'
import { balanced, legalReserve, payload, previewEntries, undoable } from '../src/equity'
import es from '../src/i18n/es.js'
import en from '../src/i18n/en.js'

const lines = (e) => e.lines.map((l) => `${l.account} ${l.debit ? 'D ' + l.debit : 'H ' + l.credit}`).join(' | ')

// Las cifras son las de los supuestos de referencia (docs del proyecto: supuestos-v0.42.0.md; base de datos: fase 55)
describe('operaciones societarias · asientos que se ven antes de contabilizar', () => {
  it('S1 · constitución de una SA con el 25 % desembolsado', () => {
    const e = previewEntries('incorporation', { capital: '60.000', paid_pct: '25' })
    expect(e.map(lines)).toEqual(['190 D 60000 | 194 H 60000', '572 D 15000 | 1030 D 45000 | 190 H 60000', '194 D 60000 | 100 H 60000'])
    expect(balanced(e)).toBe(true)
  })
  it('S2 · ampliación con prima: la prima, desembolsada entera', () => {
    const e = previewEntries('capital_increase', { nominal: '100000', premium: '20000', paid_pct: '100' })
    expect(e.map(lines)).toEqual(['190 D 120000 | 194 H 100000 | 110 H 20000', '572 D 120000 | 190 H 120000', '194 D 100000 | 100 H 100000'])
  })
  it('S1 · dividendo pasivo exigido y cobrado', () => {
    expect(previewEntries('call', { amount: '22500', paid: true }).map(lines)).toEqual(['5580 D 22500 | 1030 H 22500', '572 D 22500 | 5580 H 22500'])
    expect(previewEntries('call', { amount: '22500', paid: false })).toHaveLength(1)
  })
  it('S3 · reparto con la vista previa de la base de datos y pago con el 19 %', () => {
    const prev = { result: 50000, offset_losses: 0, legal_reserve: 2000, interim: 0, complementary: 30000, voluntary: 18000 }
    expect(previewEntries('distribution', {}, {}, prev).map(lines)).toEqual(['129 D 50000 | 112 H 2000 | 526 H 30000 | 113 H 18000'])
    expect(previewEntries('dividend_payment', { amount: '20000', withholding: true }).map(lines)).toEqual(['526 D 20000 | 47512 H 3800 | 572 H 16200'])
    expect(previewEntries('dividend_payment', { amount: '', withholding: false }, { dividend_payable: 10000 }).map(lines)).toEqual(['526 D 10000 | 572 H 10000'])
  })
  it('S4 y S5 · con dividendo a cuenta y con pérdidas', () => {
    const prev = { result: 45000, offset_losses: 0, legal_reserve: 4500, interim: 20000, complementary: 10000, voluntary: 10500 }
    expect(previewEntries('distribution', {}, {}, prev).map(lines)).toEqual(['129 D 45000 | 112 H 4500 | 557 H 20000 | 526 H 10000 | 113 H 10500'])
    expect(previewEntries('distribution', {}, {}, { result: -20000 }).map(lines)).toEqual(['121 D 20000 | 129 H 20000'])
    expect(previewEntries('interim_dividend', { amount: '20000' }).map(lines)).toEqual(['557 D 20000 | 526 H 20000'])
  })
  it('S6 · compensar con reservas y reducir el capital', () => {
    expect(previewEntries('loss_offset', { amount: '5000' }).map(lines)).toEqual(['113 D 5000 | 121 H 5000'])
    expect(previewEntries('capital_reduction', { amount: '18000' }).map(lines)).toEqual(['100 D 18000 | 121 H 18000'])
  })
  it('sin datos, sin asientos', () => {
    expect(previewEntries('incorporation', { capital: '' })).toEqual([])
    expect(previewEntries('distribution', {}, {}, null)).toEqual([])
  })
})

describe('operaciones societarias · reglas y datos', () => {
  it('reserva legal: 10 % hasta el 20 % del capital; SL de menos de 3.000 €, 20 % hasta 3.000 (misma regla que la base de datos)', () => {
    expect(legalReserve('sl', 30000, 4000, 50000)).toBe(2000)
    expect(legalReserve('sl', 30000, 0, 45000)).toBe(4500)
    expect(legalReserve('sl', 1000, 0, 8000)).toBe(1600)
    expect(legalReserve('sl', 1000, 1600, 8000)).toBe(400)
    expect(legalReserve('sa', 60000, 12000, 100000)).toBe(0)
    expect(legalReserve('sl', 30000, 0, -500)).toBe(0)
  })
  it('lo que se manda: importes en formato español y sin los campos vacíos (los pone la base de datos)', () => {
    expect(payload('distribution', { dividend: '30.000', legal_reserve: '' }, 'c', '2027-05-20')).toEqual({ company_id: 'c', date: '2027-05-20', dividend: 30000 })
    expect(payload('dividend_payment', { amount: '', withholding: false, no_withholding_reason: ' Exención art. 21 LIS ' }, 'c', 'd'))
      .toEqual({ company_id: 'c', date: 'd', no_withholding_reason: 'Exención art. 21 LIS' })
    expect(payload('incorporation', { capital: '60.000', paid_pct: '25' }, 'c', 'd')).toEqual({ company_id: 'c', date: 'd', capital: 60000, paid_pct: 25 })
  })
  it('solo se deshace la última contabilizada', () => {
    expect(undoable([{ id: 'a', code: 'SOC-0001', status: 'posted' }, { id: 'b', code: 'SOC-0002', status: 'posted' }, { id: 'c', code: 'SOC-0003', status: 'cancelled' }])).toBe('b')
    expect(undoable([])).toBe(null)
  })
  it('textos de cada operación, sus asientos y sus avisos en los dos idiomas', () => {
    for (const d of [es, en]) {
      for (const k of ['incorporation', 'capital_increase', 'reserves_to_capital', 'call', 'distribution', 'interim_dividend', 'dividend_payment', 'loss_offset', 'capital_reduction']) {
        expect(d.eq.kind[k], k).toBeTruthy()
      }
      for (const w of ['no_result', 'dividend_with_loss', 'legal_reserve_below_min', 'dividend_below_interim', 'dividend_above_available', 'net_worth_below_capital', 'losses_left', 'interim_above_limit', 'interim_no_liquidity']) {
        expect(d.eq.warn[w], w).toBeTruthy()
      }
      for (const a of ['100', '1030', '110', '112', '113', '121', '129', '190', '194', '526', '557', '5580', '572', '47512']) expect(d.eq.account[a], a).toBeTruthy()
    }
  })
})

import { friendlyError } from '../src/errors'
const tr = (dict) => (k) => k.split('.').reduce((o, x) => (o == null ? undefined : o[x]), dict) ?? k
describe('operaciones societarias · errores en lenguaje claro', () => {
  const t = tr(es)
  it('cada mensaje de la base de datos tiene su explicación y su pantalla', () => {
    const cases = [
      ['The company already has share capital: use a capital increase', /ya tiene capital/],
      ['The share capital of an SA must be at least 60,000 (art. 4.3 LSC)', /60\.000/],
      ['In an SL the capital must be fully paid at incorporation (art. 78 LSC)', /SL/],
      ['At least 25 % of the capital must be paid at incorporation (art. 79 LSC)', /25 %/],
      ['There is no result to distribute on 2027-05-20: close the previous year first', /resultado del año anterior/],
      ['The distribution is not valid: dividend_above_available', /Sociedades de Capital/],
      ['The interim dividend is not valid: interim_above_limit (art. 277 LSC)', /277/],
      ['Without withholding, say why (e.g. exemption of art. 21 LIS)', /motivo/],
      ['Use the voluntary reserves first: capital cannot be reduced for losses while there are reserves (art. 322 LSC)', /reservas voluntarias/],
      ['Undo the later equity operations first (from the last one)', /posteriores/],
      ['This entry belongs to an equity operation: undo it from Equity operations', /operación societaria/],
    ]
    for (const [msg, re] of cases) {
      const f = friendlyError(msg, t, 'es')
      expect(f.title, msg).toMatch(re)
      expect(f.technical, msg).toBe(msg)
    }
    expect(friendlyError('Not enough voluntary reserves (balance 1200.00)', t, 'es').hint).toMatch(/1\.200,00/)
    expect(friendlyError('There is no result to distribute on 2027-05-20: close the previous year first', t, 'es').to).toBe('closing')
  })
})
