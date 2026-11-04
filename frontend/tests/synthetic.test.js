import fs from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'
import { APP_VERSION, MIN_MONTHS, PROFILES, fitMonths, monthName, monthsFor, parseSeed, randomSeed, reportText } from '../src/synthetic'
import { importCard } from '../src/temporary'
import { friendlyError } from '../src/errors'
import es from '../src/i18n/es.js'
import en from '../src/i18n/en.js'
import pkg from '../package.json'
import { tEn, tEs } from './helpers.js'

// v0.59.0 · Empresas sintéticas con semilla (migración 0086)
describe('empresas sintéticas · semilla, perfil y meses', () => {
  it('la semilla: un entero de 1 a 999.999 (se aceptan espacios y puntos de miles)', () => {
    expect(parseSeed('4817')).toBe(4817)
    expect(parseSeed(' 4.817 ')).toBe(4817)
    expect(parseSeed('999999')).toBe(999999)
    for (const bad of ['0', '1000000', '-5', '4,8', 'abc', '', null, '12a']) expect(parseSeed(bad), String(bad)).toBeNull()
  })
  it('la semilla propuesta está siempre en el rango', () => {
    expect(randomSeed(() => 0)).toBe(1)
    expect(randomSeed(() => 0.9999999)).toBe(999999)
    for (let i = 0; i < 200; i++) expect(parseSeed(String(randomSeed()))).not.toBeNull()
  })
  it('los meses de cada perfil: «incidencias», de 6 a 12; los demás, de 1 a 12', () => {
    expect(monthsFor('workshop')).toEqual([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
    expect(monthsFor('incidents')).toEqual([6, 7, 8, 9, 10, 11, 12])
    expect(fitMonths('incidents', 3)).toBe(6)
    expect(fitMonths('incidents', 9)).toBe(9)
    expect(fitMonths('services', 3)).toBe(3)
  })
  it('el último mes, por su nombre', () => {
    expect(monthName(6)).toBe('junio')
    expect(monthName(12, 'en')).toBe('December')
  })
  it('dónde se crea: como al importar (un registrado, temporal y una a la vez; un miembro, si le quedan empresas)', () => {
    expect(importCard({ mode: 'temporary' }, false)).toMatchObject({ show: true, temporary: true, blocked: null })
    expect(importCard({ mode: 'temporary', company: { id: 'x' } }, true)).toMatchObject({ blocked: 'hasTemp' })
    expect(importCard({ mode: 'permanent' }, true)).toMatchObject({ show: true, temporary: false })
    expect(importCard({ mode: 'permanent' }, false).show).toBe(false)
    expect(importCard({ mode: 'none' }, true).show).toBe(false)   // un invitado, no
  })
})

describe('empresas sintéticas · copiar datos para informar de un error', () => {
  const company = { id: '11111111-2222-3333-4444-555555555555', name: 'Mi empresa secreta SL', synthetic_seed: 4817,
    synthetic_profile: 'workshop', synthetic_months: 12, work_date: '2026-12-31' }
  const txt = reportText({ company, fingerprint: 'g1-2C3AD24C', route: '#/empresa/11111111-2222-3333-4444-555555555555/tableros/impuestos', t: tEs })
  it('lleva lo necesario para reproducirlo', () => {
    expect(txt).toBe([`Mini ERP v${pkg.version}`, 'Semilla: 4817', 'Perfil: workshop (Taller)', 'Meses: 12', 'Huella: g1-2C3AD24C',
      'Pantalla: tableros/impuestos', 'Fecha de trabajo: 2026-12-31', 'Idioma: es'].join('\n'))
    expect(APP_VERSION).toBe(pkg.version)
  })
  it('y nada personal: ni el nombre de la empresa ni sus identificadores', () => {
    expect(txt).not.toContain(company.name)
    expect(txt).not.toContain(company.id)
    expect(txt).not.toMatch(/@/)
  })
  it('en inglés, y en la pantalla de inicio', () => {
    const t2 = reportText({ company, fingerprint: null, route: '#/empresa/11111111-2222-3333-4444-555555555555', language: 'en', t: tEn })
    expect(t2).toContain('Seed: 4817')
    expect(t2).toContain('Fingerprint: —')
    expect(t2).toContain('Screen: home')
  })
})

describe('empresas sintéticas · textos y errores', () => {
  it('es y en tienen las mismas claves, con un nombre para cada perfil', () => {
    const keys = (o, p = '') => Object.entries(o).flatMap(([k, v]) => (typeof v === 'object' ? keys(v, `${p}${k}.`) : [`${p}${k}`]))
    expect(keys(en.syn).sort()).toEqual(keys(es.syn).sort())
    for (const p of PROFILES) {
      expect(es.syn.profile[p], p).toBeTruthy()
      expect(MIN_MONTHS[p], p).toBeGreaterThan(0)
    }
  })
  // Cada error de la migración 0086 que puede ver la persona se explica en lenguaje claro
  const f = fileURLToPath(new URL('../../database/migrations/0086_synthetic_companies.sql', import.meta.url))
  it.skipIf(!fs.existsSync(f))('errores de la migración 0086', () => {
    const sql = fs.readFileSync(f, 'utf8')
    const msgs = [...new Set([...sql.matchAll(/raise exception '([^']+)'(?:, ([^;]+))?;/g)].map((m) => m[1]))]
      .map((m) => m.replace('The % profile needs at least % months', 'The incidents profile needs at least 6 months'))
      .filter((m) => !/^(Only the|No permission|Not allowed|Sign in|Generate into)/.test(m))
    expect(msgs.length).toBe(5)
    for (const m of msgs) {
      expect(friendlyError(m, tEs, 'es').technical, m).toBe(m)
      expect(friendlyError(m, tEn, 'en').technical, m).toBe(m)
    }
    expect(friendlyError('The incidents profile needs at least 6 months', tEs, 'es').title).toBe('Ese perfil necesita al menos 6 meses')
  })
})

// v0.59.1 · Por tandas: Supabase corta cada llamada de la web a los ~8 s
import { BATCH, BATCH_MIN, isTimeout, progressPct, runSteps } from '../src/synthetic'
describe('empresas sintéticas · por tandas (v0.59.1)', () => {
  // una base de datos de mentira: total operaciones; corta las tandas de más de «limit»
  const fakeDb = (total, limit = Infinity, failAt = null) => {
    let done = 0
    const calls = []
    const step = async (id, n) => {
      calls.push(n)
      if (n > limit) return { error: { message: 'canceling statement due to statement timeout', code: '57014' } }
      if (failAt !== null && done >= failAt) return { error: { message: 'Something else failed' } }
      done = Math.min(total, done + n)
      return { data: { company_id: id, done, total, left: total - done, date: '2026-04-15', entries: done + 3,
        fingerprint: done === total ? 'g1-2C3AD24C' : null } }
    }
    return { step, calls }
  }
  it('pide tandas de 25 hasta terminar y avisa del progreso', async () => {
    const db = fakeDb(437)
    const seen = []
    const r = await runSteps(db.step, 'c1', { onProgress: (p) => seen.push(p.done) })
    expect(r.data.left).toBe(0)
    expect(r.data.fingerprint).toBe('g1-2C3AD24C')
    expect(db.calls.every((n) => n === BATCH)).toBe(true)
    expect(seen.length).toBe(Math.ceil(437 / 25))
    expect(seen.at(-1)).toBe(437)
  })
  it('si una tanda se corta por tiempo, la repite con la mitad (25 → 12 → 6)', async () => {
    const db = fakeDb(100, 8)
    const r = await runSteps(db.step, 'c1')
    expect(r.data.left).toBe(0)
    expect(db.calls.slice(0, 3)).toEqual([25, 12, 6])
  })
  it('si ni la tanda mínima cabe, o falla otra cosa, devuelve el error (la empresa queda para continuar)', async () => {
    expect((await runSteps(fakeDb(100, 2).step, 'c1')).error.message).toMatch(/statement timeout/)
    expect(BATCH_MIN).toBe(5)
    expect((await runSteps(fakeDb(100, Infinity, 50).step, 'c1')).error.message).toBe('Something else failed')
  })
  it('reconoce el corte por tiempo y calcula el porcentaje', () => {
    expect(isTimeout({ message: 'canceling statement due to statement timeout' })).toBe(true)
    expect(isTimeout({ code: '57014' })).toBe(true)
    expect(isTimeout({ message: 'Not allowed' })).toBe(false)
    expect(progressPct({ done: 109, total: 437 })).toBe(24)
    expect(progressPct(null)).toBe(0)
  })
  it('textos del diálogo de confirmación en los dos idiomas', () => {
    expect(Object.keys(en.notice).sort()).toEqual(Object.keys(es.notice).sort())
    for (const k of ['progress', 'left', 'continue', 'unfinished']) expect(en.syn[k] && es.syn[k], k).toBeTruthy()
  })
})
