import { describe, expect, it } from 'vitest'
import { buildPgc, cardKey, pgcCodeOf, exampleTotals, filterAccounts, firstAccount, glossaryFor, linkify, nrvLabel, pgcRoute } from '../src/pgc'
import es from '../src/i18n/es.js'
import en from '../src/i18n/en.js'
import fs from 'node:fs'
import { fileURLToPath } from 'node:url'

// PGC de estudio (v0.48.0): criterios de aceptación de la especificación (SPEC_pgc_estudio.md, punto 6)
const A = (account, name) => ({ account, subgroup: account.slice(0, 2), name, statement_lines: [] })
const pgc = buildPgc({
  accounts: [A('4009', 'Proveedores, facturas pendientes de recibir o de formalizar'), A('4000', 'Proveedores (euros)'),
    A('4004', 'Proveedores (moneda extranjera)'), A('4720', 'Hacienda Pública, IVA soportado'), A('4750', 'Hacienda Pública, acreedora por IVA'),
    A('6250', 'Primas de seguros'), A('5200', 'Préstamos a corto plazo de entidades de crédito'), A('6400', 'Sueldos y salarios'), A('2100', 'Terrenos y bienes naturales')],
  cards: [{ code: '400', nrv: [9] }, { code: '4009', nrv: [9] }, { code: '472', nrv: [12] }, { code: '4750', nrv: [12] }, { code: '640', nrv: [] }],
})

describe('pgc · ficha de una cuenta', () => {
  it('de 4 dígitos si la hay; si no, la de 3 (toda la cuenta)', () => {
    expect(['4000', '4009', '4720', '4750', '2100'].map((c) => cardKey(c, pgc.cards))).toEqual(['400', '4009', '472', '4750', null])
  })
  it('la primera cuenta de 4 dígitos de un código (también de una subcuenta de 8)', () => {
    expect([firstAccount('640', pgc.accounts), firstAccount('4751', pgc.accounts), firstAccount('40000001', pgc.accounts), firstAccount('9', pgc.accounts)])
      .toEqual(['6400', null, '4000', null])
  })
  it('cada NRV sabe qué fichas la citan', () => {
    expect(pgc.nrvRefs).toEqual({ 9: ['400', '4009'], 12: ['472', '4750'] })
    expect(nrvLabel(12)).toBe('NRV 12.ª')
  })
})

describe('pgc · buscador', () => {
  const codes = (o) => filterAccounts(pgc.accounts, pgc.cards, o).map((a) => a.account)
  it('«400» encuentra 4000, 4004 y 4009, en orden', () => expect(codes({ text: '400' })).toEqual(['4000', '4004', '4009']))
  it('por nombre, sin mayúsculas ni tildes', () => {
    expect(codes({ text: 'PROVEEDORES' })).toEqual(['4000', '4004', '4009'])
    expect(codes({ text: 'credito' })).toEqual(['5200'])
  })
  it('por grupo y solo las que tienen ficha', () => {
    expect(codes({ group: '6' })).toEqual(['6250', '6400'])
    expect(codes({ onlyCards: true })).toEqual(['4000', '4004', '4009', '4720', '4750', '6400'])
  })
})

describe('pgc · enlaces entre cuentas', () => {
  it('«contra la 625» abre la 6250; un número que no es cuenta se queda como texto', () => {
    expect(linkify('Se carga contra la 625 y la 9999.', pgc.accounts))
      .toEqual([{ text: 'Se carga contra la ' }, { text: '625', go: '6250' }, { text: ' y la 9999.' }])
    expect(linkify('Ver el ejemplo de la cuenta 640.', pgc.accounts)).toEqual([{ text: 'Ver el ejemplo de la cuenta ' }, { text: '640', go: '6400' }, { text: '.' }])
    expect(linkify('Sin cuentas', pgc.accounts)).toEqual([{ text: 'Sin cuentas' }])
  })
  it('el ejemplo suma el Debe y el Haber', () => {
    expect(exampleTotals([{ debe: 10000, haber: 0 }, { debe: 700, haber: 0 }, { debe: 0, haber: 10700 }])).toEqual({ debit: 10700, credit: 10700 })
  })
  it('términos del glosario de la cuenta', () => {
    expect(glossaryFor('4000')).toContain('partner')
    expect(glossaryFor('1290')).toContain('closing')
  })
})

describe('pgc · en Nuevo asiento', () => {
  it('la ficha de la línea: los 4 primeros dígitos de la subcuenta, o nada si aún no hay 3', () => {
    expect(['47200007', '572', ' 6400 ', '57', 'caja', '', null].map(pgcCodeOf)).toEqual(['4720', '572', '6400', null, null, null, null])
  })
})

describe('pgc · rutas', () => {
  it('#/pgc/6400 · #/pgc/nrv/12 · #/pgc/principios', () => {
    expect([pgcRoute([]), pgcRoute(['6400']), pgcRoute(['nrv', '12']), pgcRoute(['nrv']), pgcRoute(['principios']), pgcRoute(['xx'])]).toEqual([
      { tab: 'accounts', account: null }, { tab: 'accounts', account: '6400' }, { tab: 'nrv', nrv: 12 }, { tab: 'nrv', nrv: null },
      { tab: 'principles' }, { tab: 'accounts', account: null }])
  })
})

describe('pgc · textos', () => {
  it('es y en tienen los mismos', () => expect(Object.keys(en.pgc).sort()).toEqual(Object.keys(es.pgc).sort()))
  // Con los datos de verdad (migración 0071): las referencias de los criterios de aceptación se enlazan
  const f = fileURLToPath(new URL('../../database/migrations/0071_pgc_study.sql', import.meta.url))
  it.skipIf(!fs.existsSync(f))('datos de la migración: 712 cuentas y «contra la 480» de la ficha 625', () => {
    const sql = fs.readFileSync(f, 'utf8')
    const accounts = [...sql.matchAll(/^\('(\d{4})', '(\d{2})', '((?:[^']|'')*)'/gm)].map((m) => A(m[1], m[3]))
    expect(accounts.length).toBe(712)
    // (la especificación ponía «contra la 625» en la 480: en los datos va al revés, en la 625 y en la 490)
    const card = (c) => sql.split('\n').find((l) => l.startsWith(`('${c}', `))
    expect(card('625')).toContain('contra la 480')
    expect(card('490')).toContain('contra la 794')
    expect(linkify('contra la 480', accounts)[1]).toEqual({ text: '480', go: '4800' })
    expect(linkify('contra la 794', accounts)[1]).toEqual({ text: '794', go: '7940' })
    expect(firstAccount('640', accounts)).toBe('6400')
    expect(accounts.find((a) => a.account === '6400').name).toBe('Sueldos y salarios')
  })
})
