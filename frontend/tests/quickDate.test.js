import { describe, expect, it } from 'vitest'
import { addDays, outsideMonth, parseQuickDate, showDate } from '../src/quickDate'
import { defaultStart, monthName, nextMonth } from '../src/monthly'
import { friendlyError } from '../src/errors'
import es from '../src/i18n/es.js'
import en from '../src/i18n/en.js'

const tr = (d) => (k) => k.split('.').reduce((o, p) => o?.[p], d) ?? k
const base = '2026-02-10'   // mes de trabajo: febrero de 2026
const today = '2026-10-26'
const q = (s) => parseQuickDate(s, base, today)

// Mejora de uso 8 (mejoras-de-uso.md): como ContaSol, el día solo y el mes y el año del mes de trabajo
describe('fecha rápida', () => {
  it('solo el día: el mes y el año del mes de trabajo', () => {
    expect([q('2'), q('02'), q(' 28 ')]).toEqual(['2026-02-02', '2026-02-02', '2026-02-28'])
  })
  it('día y mes, con o sin separador', () => {
    expect([q('15/3'), q('15-3'), q('15.03'), q('1503'), q('153')]).toEqual(Array(5).fill('2026-03-15'))
  })
  it('la fecha entera, con el año de 2 o de 4 cifras, e ISO', () => {
    expect([q('15/3/25'), q('150325'), q('15032025'), q('15/03/2025'), q('2025-03-15')]).toEqual(Array(5).fill('2025-03-15'))
  })
  it('hoy, y lo que no es una fecha', () => {
    expect(q('h')).toBe(today)
    expect([q('30'), q('31/4'), q('00'), q('abc'), q(''), q('1/13')]).toEqual([null, null, null, null, null, null])   // febrero no tiene 30
  })
  it('se enseña dd/mm/aaaa; ↑ ↓ un día; fuera del mes abierto', () => {
    expect(showDate('2026-02-02')).toBe('02/02/2026')
    expect([addDays('2026-02-28', 1), addDays('2026-01-01', -1)]).toEqual(['2026-03-01', '2025-12-31'])
    const r = { from: '2026-02-01', to: '2026-02-28' }
    expect([outsideMonth('2026-01-31', r), outsideMonth('2026-02-15', r), outsideMonth('2026-03-01', r), outsideMonth('2026-03-01', null)])
      .toEqual(['before', null, 'after', null])
  })
})

// Mejora de uso 7: contabilidad mes a mes (el mes abierto lo decide la base de datos, fase 63)
describe('mes a mes', () => {
  it('nombres de los meses y el siguiente', () => {
    expect([monthName(2, 'es'), monthName(12, 'en')]).toEqual(['Febrero', 'December'])
    expect([nextMonth(2026, 2), nextMonth(2026, 12)]).toEqual([{ year: 2026, month: 3 }, { year: 2027, month: 1 }])
    expect(defaultStart('2026-10-26')).toBe('2026-01-01')
  })
  it('los errores del motor, en lenguaje claro', () => {
    const t = tr(es)
    const e = friendlyError('Monthly accounting: the open month is 02/2026 (01/02/2026 to 28/02/2026); close it before posting on 03/03/2026', t, 'es')
    expect(e.title).toBe('El mes abierto es 02/2026')
    expect(e.hint).toMatch(/del 01\/02\/2026 al 28\/02\/2026.*del 03\/03\/2026/)
    expect(friendlyError('Review and accept the warnings before closing the month', t, 'es').title).toMatch(/cerrar el mes/)
    expect(friendlyError('Review and accept the warnings before closing the year', t, 'es').title).not.toMatch(/el mes/)
    expect(friendlyError('December is closed with the year-end closing', tr(en), 'en').to).toBe('closing')
  })
  it('es y en tienen los mismos textos', () => {
    const keys = (o, p = '') => Object.entries(o).flatMap(([k, v]) => (v && typeof v === 'object' ? keys(v, `${p}${k}.`) : [`${p}${k}`]))
    expect(keys(en.mm).sort()).toEqual(keys(es.mm).sort())
    expect(keys(en.qd).sort()).toEqual(keys(es.qd).sort())
  })
})
