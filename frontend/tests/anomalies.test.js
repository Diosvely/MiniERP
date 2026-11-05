import { describe, it, expect } from 'vitest'
import { anomalyCounts, anomalyByAccount } from '../src/anomalies.js'

// v0.57.0 · el aviso de saldos al revés del Balance: cada cuenta cuenta en su partida y en las que la contienen
describe('saldos al revés en el Balance', () => {
  const rows = [
    { code: 'ACT', parent: null }, { code: 'AC', parent: 'ACT' }, { code: 'AC.I', parent: 'AC' },
    { code: 'PNP', parent: null }, { code: 'PC', parent: 'PNP' }, { code: 'PC.II.1', parent: 'PC' },
  ]
  it('en la partida y en sus partidas superiores, con los imposibles aparte', () => {
    const m = anomalyCounts(rows, [
      { line_code: 'AC.I', account_no: '40000002', severity: 'warning' },
      { line_code: 'PC.II.1', account_no: '57000001', severity: 'error' },
      { line_code: 'AC.I', account_no: '40000003', severity: 'warning' },
    ])
    expect(m['AC.I']).toEqual({ n: 2, errors: 0 })
    expect(m.ACT).toEqual({ n: 2, errors: 0 })
    expect(m['PC.II.1']).toEqual({ n: 1, errors: 1 })
    expect(m.PNP).toEqual({ n: 1, errors: 1 })
    expect(m['PN']).toBeUndefined()
  })
  it('sin cuentas al revés, nada; y una partida que no está en el Balance no se pierde', () => {
    expect(anomalyCounts(rows, [])).toEqual({})
    expect(anomalyCounts(rows, null)).toEqual({})
    expect(anomalyCounts(rows, [{ line_code: 'XX', severity: 'warning' }])).toEqual({ XX: { n: 1, errors: 0 } })
  })
  it('por número de cuenta, para marcarla al desplegar', () => {
    const by = anomalyByAccount([{ account_no: '11300001', note: 'Saldo acreedor.' }])
    expect(by.get('11300001').note).toBe('Saldo acreedor.')
    expect(by.get('57200001')).toBeUndefined()
  })
})

// v0.59.2 · Al desplegar una partida con sublíneas, cada cuenta dice en cuál se presenta
import { accountSubLine } from '../src/anomalies'
describe('cuentas de una partida con sublíneas (v0.59.2)', () => {
  const rows = [{ code: 'PC.II', label: 'II. Deudas a corto plazo' }, { code: 'PC.II.1', label: '1. Deudas con entidades de crédito' }]
  it('el banco en descubierto, desplegando «II. Deudas a corto plazo», va a «1. Deudas con entidades de crédito»', () => {
    expect(accountSubLine({ account_no: '57200000', line_code: 'PC.II.1' }, 'PC.II', rows).label).toBe('1. Deudas con entidades de crédito')
  })
  it('desplegando su propia sublínea, no se repite', () => {
    expect(accountSubLine({ account_no: '57200000', line_code: 'PC.II.1' }, 'PC.II.1', rows)).toBeNull()
    expect(accountSubLine({ account_no: 'x' }, 'PC.II', rows)).toBeNull()
  })
})
