import { describe, expect, it } from 'vitest'
import { setFlash, takeFlash } from '../src/flash'
import { filterEntries, monthRange, rangeDates, rowTarget, selectable, sourcesOf, summary } from '../src/entries'
import es from '../src/i18n/es.js'
import en from '../src/i18n/en.js'
import fs from 'node:fs'
import { fileURLToPath } from 'node:url'

const rows = [
  { entry_id: 'a', fiscal_year: 2026, entry_no: 7, status: 'posted', state: 'posted', source: 'invoice', description: 'Venta de recambios', document_no: 'F-12', total_debit: 2140, total_credit: 2140 },
  { entry_id: 'b', fiscal_year: 2026, entry_no: null, status: 'draft', state: 'ok', source: 'manual', description: 'Alquiler febrero', document_no: null, total_debit: 800, total_credit: 800 },
  { entry_id: 'c', fiscal_year: 2026, entry_no: null, status: 'draft', state: 'error', problem: 'unbalanced', source: 'manual', description: 'Seguro', document_no: null, total_debit: 1200, total_credit: 0 },
]

// Mejora de uso 9 (mejoras-de-uso.md): la pantalla «Asientos». La lista y el estado los da la base de datos (fase 64)
describe('asientos · fechas', () => {
  it('mes actual: el mes abierto o el de la fecha de trabajo', () => {
    expect(monthRange('2026-02-14')).toEqual({ from: '2026-02-01', to: '2026-02-28' })
    expect(monthRange('2026-12-31')).toEqual({ from: '2026-12-01', to: '2026-12-31' })
    expect(monthRange('2026-03-20', { from: '2026-03-15', to: '2026-03-31' })).toEqual({ from: '2026-03-15', to: '2026-03-31' })
  })
  it('los tres botones', () => {
    const c = { workDate: '2026-02-14', from: '2026-01-10', to: '' }
    expect([rangeDates('month', c), rangeDates('range', c), rangeDates('all', c)])
      .toEqual([{ from: '2026-02-01', to: '2026-02-28' }, { from: '2026-01-10', to: null }, { from: null, to: null }])
  })
})

describe('asientos · filtros, totales y clic', () => {
  it('por estado, origen y texto (nº, concepto o documento, sin acentos)', () => {
    expect(filterEntries(rows, { state: 'error' }).map((r) => r.entry_id)).toEqual(['c'])
    expect(filterEntries(rows, { source: 'manual' }).map((r) => r.entry_id)).toEqual(['b', 'c'])
    expect(filterEntries(rows, { text: '7' }).map((r) => r.entry_id)).toEqual(['a'])
    expect(filterEntries(rows, { text: 'f-12' }).map((r) => r.entry_id)).toEqual(['a'])
    expect(filterEntries(rows, { text: 'alquiler' }).map((r) => r.entry_id)).toEqual(['b'])
    expect(sourcesOf(rows)).toEqual(['invoice', 'manual'])
  })
  it('totales y cuántos de cada estado', () => {
    expect(summary(rows)).toEqual({ debit: 4140, credit: 2940, posted: 1, ok: 1, error: 1 })
  })
  it('un contabilizado abre su ficha; un borrador, Nuevo asiento; solo se marcan los «en edición»', () => {
    expect(rows.map(rowTarget)).toEqual(['asiento/2026/7', 'entry/b', 'entry/c'])
    expect(rows.map(selectable)).toEqual([false, true, false])
  })
})

describe('asientos · textos', () => {
  it('es y en tienen los mismos', () => {
    const keys = (o, p = '') => Object.entries(o).flatMap(([k, v]) => (v && typeof v === 'object' ? keys(v, `${p}${k}.`) : [`${p}${k}`]))
    expect(keys(en.ent).sort()).toEqual(keys(es.ent).sort())
  })
  // Cada origen y cada motivo que puede dar la base de datos (0070) tiene su nombre
  const f = fileURLToPath(new URL('../../database/migrations/0070_entries_screen.sql', import.meta.url))
  it.skipIf(!fs.existsSync(f))('orígenes y motivos de la base de datos', () => {
    const sql = fs.readFileSync(f, 'utf8')
    const sources = [...sql.matchAll(/THEN '(\w+)'::text/g)].map((m) => m[1]).concat(['manual'])
    const problems = [...sql.matchAll(/return '(\w+)';/g)].map((m) => m[1])
    expect(sources.length).toBeGreaterThan(15)
    expect(problems.length).toBe(9)
    for (const x of sources) expect(es.ent.source[x], x).toBeTruthy()
    for (const x of problems) expect(es.ent.problem[x], x).toBeTruthy()
  })
})

describe('asientos · al volver de Nuevo asiento', () => {
  it('el mensaje se enseña una vez', () => {
    setFlash('Contabilizado con el nº 15.')
    expect([takeFlash(), takeFlash()]).toEqual(['Contabilizado con el nº 15.', null])
  })
})
