import { describe, expect, it } from 'vitest'
import { counts, entryList, entrySection, exportRows, groupCompare, overall, progress, rowLabel, screenOf } from '../src/cases'
import { friendlyError } from '../src/errors'
import es from '../src/i18n/es.js'
import en from '../src/i18n/en.js'
import fs from 'node:fs'
import { fileURLToPath } from 'node:url'

const tr = (d) => (k) => k.split('.').reduce((o, p) => o?.[p], d) ?? k
const t = tr(es)
const r = (kind, code, status, extra = {}) => ({ kind, code, status, expected: 100, actual: status === 'ok' ? 100 : 90, difference: status === 'ok' ? 0 : -10, ...extra })

// Las cifras son las del caso «Taller Atlántico SL» (supuestos-v0.45.0.md; base de datos: fases 61 y 62)
describe('casos completos · la comparación', () => {
  const rows = [r('balance', 'ACT', 'ok', { label: 'TOTAL ACTIVO', label_en: 'TOTAL ASSETS' }), r('pyg', 'PD', 'pending'), r('pyg', 'P1', 'ok'),
    r('cf_direct', 'DB1', 'diff'), r('tax_form', '1.45', 'ok'), r('withholding', '4.111', 'ok')]
  it('por grupos, en el orden de las cuentas anuales, con sus cuentas', () => {
    const g = groupCompare(rows)
    expect(g.map((x) => x.kind)).toEqual(['pyg', 'balance', 'cf_direct', 'tax_form', 'withholding'])
    expect(g[0]).toMatchObject({ screen: 'pyg', total: 2, ok: 1, pending: 1, diff: 0 })
    expect(g.map(overall)).toEqual(['pending', 'ok', 'diff', 'ok', 'ok'])
    expect(overall(counts(rows))).toBe('diff')
    expect(overall(counts(rows.filter((x) => x.status !== 'diff')))).toBe('pending')
  })
  it('cada grupo abre su pantalla', () => {
    expect([screenOf('cf_indirect'), screenOf('cit'), screenOf('tax_form'), screenOf('withholding'), screenOf('ecpn')])
      .toEqual(['cashflow', 'corporate_tax', 'forms', 'withholdings', 'ecpn'])
  })
  it('el nombre de cada partida: el de la base de datos o el de la web', () => {
    expect(rowLabel(rows[0], t, 'es')).toBe('TOTAL ACTIVO')
    expect(rowLabel(rows[0], tr(en), 'en')).toBe('TOTAL ASSETS')
    expect(rowLabel(r('tax_form', '2.45', 'ok'), t, 'es')).toBe('2T · casilla 45')
    expect(rowLabel(r('withholding', '4.111', 'ok'), tr(en), 'en')).toBe('Q4 · form 111')
    expect(rowLabel(r('ecpn', 'part_a.total', 'ok'), t, 'es')).toMatch(/^TOTAL DE INGRESOS Y GASTOS RECONOCIDOS/)
    expect(rowLabel(r('ecpn', 'part_b.owners.capital', 'ok'), t, 'es')).toBe('II. Operaciones con socios o propietarios · Capital')
    expect(rowLabel(r('ecpn', 'end', 'ok'), t, 'es', 2026)).toBe('Saldo al final de 2026')
    expect(rowLabel(r('ecpn', 'balance_net_worth', 'ok'), t, 'es')).toBe('Patrimonio neto del balance')
    expect(rowLabel(r('cit', 'taxable_base', 'ok'), t, 'es')).toBe('Base imponible')
    expect(rowLabel(r('cit', 'equity_tax_effect', 'ok'), t, 'es')).toMatch(/reservas \(113\)/)
  })
  it('a Excel, con su grupo y su estado', () => {
    expect(exportRows([rows[3]], t, 'es')[0]).toEqual({ group: 'Flujos de efectivo (método directo)', code: 'DB1', label: 'DB1',
      expected: 100, actual: 90, difference: -10, status: 'Diferencia' })
  })
})

describe('casos completos · las operaciones', () => {
  const steps = [1, 2, 11, 19].map((n) => ({ n, phase: n > 10 ? 'closing' : 'year', status: n < 11 ? 'done' : 'pending',
    entries: n === 1 ? [{ entry_id: 'a', year: 2026, entry_no: 1 }, { entry_id: 'b', year: 2026, entry_no: 2 }, { entry_id: 'c', year: 2026, entry_no: 3 }] : [] }))
  it('hechas, y las del año y las del cierre por separado', () => {
    const p = progress(steps)
    expect([p.done, p.total, p.year.length, p.closing.length]).toEqual([2, 4, 2, 2])
  })
  it('sus asientos: los primeros y cuántos más, con su enlace', () => {
    expect(entryList(steps[0].entries, 2)).toEqual({ shown: steps[0].entries.slice(0, 2), more: 1 })
    expect(entrySection({ year: 2027, entry_no: 1 })).toBe('asiento/2027/1')
  })
})

describe('casos completos · textos y errores', () => {
  it('es y en tienen los mismos textos', () => {
    const keys = (o, p = '') => Object.entries(o).flatMap(([k, v]) => (v && typeof v === 'object' ? keys(v, `${p}${k}.`) : [`${p}${k}`]))
    expect(keys(en.cs).sort()).toEqual(keys(es.cs).sort())
    expect(es.nav.case.label && en.nav.case.label).toBeTruthy()
  })
  it('los errores de la base de datos, en lenguaje claro', () => {
    expect(friendlyError('Load the case into a new company: this one already has entries', t, 'es').title).toMatch(/ya tiene asientos/)
    expect(friendlyError('This case needs a company in the Canary Islands (IGIC)', t, 'es').title).toMatch(/canaria/)
    expect(friendlyError('No permission: only the company admin can load a case', t, 'es').title).toMatch(/administrador/)
    expect(friendlyError('Unknown case: x', tr(en), 'en').title).toMatch(/does not exist/)
  })
  // Cada operación del caso (erp.case_steps, 0067) abre una pantalla que existe, con su nombre en el menú
  const dir = fileURLToPath(new URL('../../database/migrations', import.meta.url))
  const f = `${dir}/0067_case_screen.sql`
  it.skipIf(!fs.existsSync(f))('las pantallas de las operaciones existen', () => {
    const sql = fs.readFileSync(f, 'utf8')
    const screens = new Set([...sql.matchAll(/'(\w+)', (?:null|'\w+')\)[,;]/g)].map((m) => m[1]))
    expect(screens.size).toBeGreaterThanOrEqual(8)
    for (const s of screens) expect(es.nav[s]?.label, s).toBeTruthy()
  })
})
