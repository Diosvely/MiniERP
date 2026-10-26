import { describe, expect, it } from 'vitest'
import { HEARTBEAT_MS, idleText, importCard, leaveRequest, tooManyLines } from '../src/temporary'
import { friendlyError } from '../src/errors'
import { tEn, tEs } from './helpers.js'
import es from '../src/i18n/es.js'
import en from '../src/i18n/en.js'
import fs from 'node:fs'
import { fileURLToPath } from 'node:url'

// Empresas temporales de los registrados (v0.49.0, diseno-v0.49.0.md): lo decide la base de datos (fase 66);
// aquí, qué enseña la web
const status = (x = {}) => ({ mode: 'temporary', idle_minutes: 120, max_hours: 48, max_lines_per_import: 20000, ai_daily_limit: 5,
  company: null, full: false, ...x })

describe('temporales · la tarjeta «Importar»', () => {
  it('el owner y los miembros, como siempre (si les quedan empresas); sin la migración, también como antes', () => {
    expect(importCard(status({ mode: 'permanent' }), true)).toEqual({ show: true, temporary: false })
    expect(importCard(status({ mode: 'permanent' }), false)).toEqual({ show: false, temporary: false })
    expect(importCard(null, true)).toEqual({ show: true, temporary: false })
  })
  it('un registrado, en temporal aunque ya haya gastado su empresa propia', () => {
    expect(importCard(status(), false)).toEqual({ show: true, temporary: true, blocked: null })
  })
  it('si ya tiene una temporal o está lleno, lo dice en lugar del botón', () => {
    expect(importCard(status({ company: { id: 'x' } }), true).blocked).toBe('hasTemp')
    expect(importCard(status({ full: true }), true).blocked).toBe('full')
  })
  it('el invitado de la demo, nada', () => {
    expect(importCard(status({ mode: 'none' }), false).show).toBe(false)
  })
  it('el tope de líneas solo vale para las temporales', () => {
    expect([tooManyLines(status(), 20000), tooManyLines(status(), 20001), tooManyLines(status({ mode: 'permanent' }), 90000), tooManyLines(null, 90000)])
      .toEqual([false, true, false, false])
  })
})

describe('temporales · latido y salida', () => {
  it('latido cada 5 minutos; 120 minutos se leen «2 h»', () => {
    expect(HEARTBEAT_MS).toBe(300000)
    expect([idleText(120), idleText(90)]).toEqual(['2 h', '90 min'])
  })
  it('al cerrar la pestaña: temp_leave con keepalive y la sesión del usuario', () => {
    const [url, init] = leaveRequest('https://x.supabase.co', 'pk', 'tok')
    expect(url).toBe('https://x.supabase.co/rest/v1/rpc/temp_leave')
    expect(init).toMatchObject({ method: 'POST', keepalive: true })
    expect(init.headers).toMatchObject({ apikey: 'pk', Authorization: 'Bearer tok', 'Content-Profile': 'erp' })
  })
})

describe('temporales · textos y errores', () => {
  it('es y en tienen los mismos', () => expect(Object.keys(en.tmp).sort()).toEqual(Object.keys(es.tmp).sort()))
  // Cada error de la migración 0072 se explica en lenguaje claro
  const f = fileURLToPath(new URL('../../database/migrations/0072_temporary_companies.sql', import.meta.url))
  it.skipIf(!fs.existsSync(f))('errores de la migración 0072', () => {
    const sql = fs.readFileSync(f, 'utf8')
    const msgs = [...new Set([...sql.matchAll(/raise exception '([^']+)'/g)].map((m) => m[1].replace(/%/g, '7')))]
      .filter((m) => !/^(Guest|Company limit|Only the application|The AI|Daily AI|Only the company)/.test(m))
    expect(msgs.length).toBe(5)
    for (const m of msgs) {
      expect(friendlyError(m, tEs, 'es').technical, m).toBe(m)   // reconocido (si no, se muestra tal cual, sin «technical»)
      expect(friendlyError(m, tEn, 'en').technical, m).toBe(m)
    }
    expect(friendlyError('Too many lines for a temporary import: 25000 (maximum 20000)', tEs, 'es').title)
      .toBe('El fichero tiene 25000 líneas y en una empresa temporal caben 20000')
  })
})
