import { describe, expect, it } from 'vitest'
import fs from 'node:fs'
import { fileURLToPath } from 'node:url'
import { GLOSSARY, SECTION_TERM } from '../src/glossary'
import { conceptRow } from './glossarySql'

// La copia del glosario en la base de datos (erp.concepts) sale de las migraciones: para cada término vale la
// última fila que lo inserta. Si cambias src/glossary.js, añade una migración con las filas nuevas (tests/glossarySql.js).
const dir = fileURLToPath(new URL('../../database/migrations', import.meta.url))
const hasDb = fs.existsSync(dir)
function lastRows() {
  const rows = {}
  for (const f of fs.readdirSync(dir).filter((x) => x.endsWith('.sql')).sort()) {
    const sql = fs.readFileSync(`${dir}/${f}`, 'utf8')
    if (!sql.includes('erp.concepts')) continue
    // Solo las filas de «insert into erp.concepts … values» (otras tablas, como erp.operations, también tienen claves
    // con el mismo aspecto). Windows: las migraciones pueden tener CRLF
    let inConcepts = false
    for (const line of sql.split(/\r?\n/)) {
      if (/^insert into erp\.concepts\b/i.test(line)) { inConcepts = true; continue }
      if (!inConcepts) continue
      const m = line.match(/^\('([A-Za-z]+)', \d+, /)
      if (m) rows[m[1]] = line.replace(/,$/, '')
      else inConcepts = false
    }
  }
  return rows
}

describe('glosario', () => {
  it('cada término tiene los dos idiomas, BC y SAP', () => {
    for (const [k, g] of Object.entries(GLOSSARY)) {
      expect(g.es?.term && g.es?.def && g.en?.term && g.en?.def, k).toBeTruthy()
      expect(g.bc && g.sap, k).toBeTruthy()
      expect(Boolean(g.es.ex) === Boolean(g.en.ex), `${k}: ejemplo en un solo idioma`).toBe(true)
      for (const p of g.pgc ?? []) expect(p, k).toMatch(/^\d{1,4}$/)
    }
  })
  it('cada pantalla apunta a un término que existe', () => {
    for (const id of Object.values(SECTION_TERM)) expect(GLOSSARY[id], id).toBeDefined()
  })
  it.runIf(hasDb)('la copia de la base de datos (erp.concepts) coincide con src/glossary.js', () => {
    const rows = lastRows()
    Object.entries(GLOSSARY).forEach(([k, g], i) => {
      expect(rows[k], `falta "${k}" en las migraciones`).toBeDefined()
      expect(rows[k].replace(/^\('[A-Za-z]+', \d+, /, ''), `"${k}" cambió: añade una migración`)
        .toBe(conceptRow(k, g, (i + 1) * 10).replace(/^\('[A-Za-z]+', \d+, /, ''))
    })
  })
})
