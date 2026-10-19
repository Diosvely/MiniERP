import { describe, expect, it } from 'vitest'
import fs from 'node:fs'
import { fileURLToPath } from 'node:url'
import { SOURCES } from '../src/sources'
import { sourceRow } from './sourcesSql'

// La copia de la base documental en la base de datos (erp.sources) sale de las migraciones: para cada fuente vale la
// última fila que la inserta. Si cambias src/sources.js, añade una migración con las filas nuevas (tests/sourcesSql.js).
const dir = fileURLToPath(new URL('../../database/migrations', import.meta.url))
const hasDb = fs.existsSync(dir)
function lastRows() {
  const rows = {}
  for (const f of fs.readdirSync(dir).filter((x) => x.endsWith('.sql')).sort()) {
    const sql = fs.readFileSync(`${dir}/${f}`, 'utf8')
    if (!sql.includes('erp.sources')) continue
    for (const line of sql.split(/\r?\n/)) {
      const m = line.match(/^\('([a-z0-9_]+)', '(AEAT|ATC|BOE)', /)
      if (m) rows[m[1]] = line.replace(/,$/, '')
    }
  }
  return rows
}

describe('base documental', () => {
  it.runIf(hasDb)('la copia de la base de datos (erp.sources) coincide con src/sources.js', () => {
    const rows = lastRows()
    for (const [k, s] of Object.entries(SOURCES)) {
      expect(rows[k], `falta "${k}" en las migraciones`).toBeDefined()
      expect(rows[k], `"${k}" cambió: añade una migración`).toBe(sourceRow(k, s))
    }
  })
})
