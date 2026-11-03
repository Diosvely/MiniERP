import fs from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'
import { friendlyError } from '../src/errors'
import es from '../src/i18n/es.js'
import en from '../src/i18n/en.js'
import { tEn, tEs } from './helpers.js'
import { MATRIX_ACTION, MATRIX_COLUMN, ROLE_ACTIONS, ROLE_CAPS } from '../src/roles'

// v0.58.0 · «Lo tuyo, todo; lo de otro, nada» (migración 0085). Quién usa la IA lo decide la base de datos
// (erp.ai_status); la web solo enseña el panel si la respuesta dice «allowed».

describe('permisos (v0.58.0)', () => {
  const f = fileURLToPath(new URL('../../database/migrations/0085_permissions_ownership.sql', import.meta.url))
  it.skipIf(!fs.existsSync(f))('cada error nuevo de la migración 0085 se explica en lenguaje claro', () => {
    const sql = fs.readFileSync(f, 'utf8')
    const msgs = [...new Set([...sql.matchAll(/raise exception '([^']+)'/g)].map((m) => m[1].replace(/%/g, 'x@y.es')))]
      .filter((m) => /^Only/.test(m))
    expect(msgs.length).toBe(3)
    for (const m of msgs) {
      expect(friendlyError(m, tEs, 'es').technical, m).toBe(m)
      expect(friendlyError(m, tEn, 'en').technical, m).toBe(m)
    }
    expect(friendlyError('Only the application owner can manage access, and only in the companies they administer', tEs, 'es').title)
      .toBe('Solo el propietario de la aplicación puede hacerlo')
  })
  it('los textos de la IA dicen quién la usa: quien administra la empresa y el titular de los datos', () => {
    expect(es.aiPanelNotAllowed).toMatch(/administra/)
    expect(en.aiPanelNotAllowed).toMatch(/administers/)
    expect(es.err.aiNotEnabled.hint).toMatch(/administra/)
    expect(en.err.aiNotEnabled.hint).toMatch(/administers/)
  })
})

describe('qué puede hacer cada rol (v0.58.0)', () => {
  const doc = fileURLToPath(new URL('../../docs/permisos.md', import.meta.url))
  // La tabla de la pantalla Accesos dice lo mismo que la matriz que exige la prueba (docs/permisos.md, generado de ella)
  it.skipIf(!fs.existsSync(doc))('coincide con docs/permisos.md', () => {
    const lineas = fs.readFileSync(doc, 'utf8').split('\n').filter((l) => l.startsWith('| '))
    const cabecera = lineas.find((l) => l.startsWith('| Grupo | Acción | Sin sesión')).split('|').map((x) => x.trim())
    for (const [role, caps] of Object.entries(ROLE_CAPS)) {
      const col = cabecera.indexOf(MATRIX_COLUMN[role])
      expect(col, role).toBeGreaterThan(0)
      for (const a of ROLE_ACTIONS) {
        const fila = lineas.find((l) => l.split('|')[2]?.trim() === MATRIX_ACTION[a]).split('|').map((x) => x.trim())
        expect(fila[col] === '✓', `${role} · ${a}`).toBe(caps[a])
      }
    }
  })
  it('textos en los dos idiomas', () => {
    for (const k of ['accessRolesTitle', 'accessRolesIntro', 'accessRole', 'accessDataOwnerRole', 'accessYes', 'accessNo', 'accessRolesRules']) {
      expect(es[k], k).toBeTruthy()
      expect(en[k], k).toBeTruthy()
    }
    for (const a of ROLE_ACTIONS) {
      expect(es.accessCan[a], a).toBeTruthy()
      expect(en.accessCan[a], a).toBeTruthy()
    }
  })
})
