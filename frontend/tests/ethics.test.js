import { describe, expect, it } from 'vitest'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { execFileSync } from 'node:child_process'

// v0.60.1 · Revisión ética (mini-erp/docs/revision-etica.md, decisión de Diosvely del 07-11-2026 y del 08-11-2026):
// el contenido es didáctico. En nada de lo que se lee (textos de la web, documentación, ADR, comentarios del código y
// de las migraciones) se nombra ni se compara un programa contable comercial, ni se contraponen los dos modos de
// control como «los de SAP / BC» frente a «los de los ERP españoles». Business Central y SAP sí se pueden citar como
// referencia de buenas prácticas.
// Se quedan, porque no se leen en pantalla, el valor interno 'sage' del importador y la función fromSage (opción A).
// «Regla A3» (nuestra regla de validar) y PN.A3 (la partida A-3 del patrimonio neto) no son nombres de programas.

const ROOT = fileURLToPath(new URL('../../', import.meta.url))
const EXT = /\.(js|jsx|mjs|sql|md|html|json|css)$/
// Las dos pruebas de esta regla contienen los nombres a propósito, para comprobar que se detectan
const SELF = [path.join('tests', 'ethics.test.js'), 'test_fase83_ethics.sql']

// Solo los archivos del repositorio: los que Git sigue o seguiría (git ls-files, sin los ignorados). Así no se leen
// node_modules, dist, los scripts aplicar-*.mjs ni los datos privados que .gitignore deja fuera del repositorio
// (regresión: en el PC de Diosvely, recorrer la carpeta entera tardaba más de 30 s).
function repoFiles() {
  try {
    const out = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard'], { cwd: ROOT, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 })
    return out.split(/\r?\n/).filter((f) => f && EXT.test(f) && !SELF.some((x) => f.endsWith(x.split(path.sep).join('/'))))
      .map((f) => path.join(ROOT, f)).filter((f) => fs.existsSync(f))
  } catch {
    return null   // sin Git (por ejemplo, una copia descargada en .zip): la prueba se salta
  }
}
const FILES = repoFiles()

export const NAMES = /\b(ContaSol|Sage|SAGE|A3ECO|ContaPlus|Versat|DELSOL)\b|\bA3\b(?!\))/
export const CONTRAST = /ERPs? español(es)?|Spanish ERPs?|estilo español/i
const ALLOWED = [/regla A3/i, /\(A3\)/, /PN\.A3/, /A-3\)/]

const ALLOWED_G = ALLOWED.map((re) => new RegExp(re.source, re.flags + 'g'))   // compiladas una sola vez
const ANY = new RegExp(`${NAMES.source}|${CONTRAST.source}`, 'i')

export function offending(text) {
  // v0.60.4 · primero una búsqueda rápida en el archivo entero: casi ninguno tiene nada y se salta sin partirlo en líneas
  // (regresión: en el PC de Diosvely, grabando la pantalla, la prueba pasó de los 30 s)
  if (!ANY.test(text)) return []
  return text.split(/\r?\n/).filter((l) => {
    const clean = ALLOWED_G.reduce((s, re) => s.replace(re, ''), l)
    return NAMES.test(clean) || CONTRAST.test(clean)
  })
}

describe('revisión ética: sin nombres de programas comerciales', () => {
  it('detecta un nombre y deja pasar las excepciones (regresión, regla A1)', () => {
    expect(offending('Fecha rápida como ContaSol')).toHaveLength(1)
    expect(offending('Guiado (como los ERP españoles)')).toHaveLength(1)
    expect(offending("importSource: { sage: 'Diario en Excel' }")).toHaveLength(0)
    expect(offending('const rows = fromSage(sheet)')).toHaveLength(0)
    expect(offending('pendientes de validar (regla A3)')).toHaveLength(0)
    expect(offending("('PN.A3', 'PN', 540, 'A-3) Subvenciones')")).toHaveLength(0)
    expect(offending('Estricto (como SAP o Business Central)')).toHaveLength(0) // referencia: la regla CONTRAST la caza si se contrapone
  })

  it.runIf(FILES !== null)('ningún archivo del repositorio los nombra', () => {
    const found = []
    for (const f of FILES) {
      for (const l of offending(fs.readFileSync(f, 'utf8'))) found.push(`${path.relative(ROOT, f)}: ${l.trim().slice(0, 120)}`)
    }
    expect(found).toEqual([])
  }, 120000)   // margen para un PC cargado: recorre todo el repositorio
})
