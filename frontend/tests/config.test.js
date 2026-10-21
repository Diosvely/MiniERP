import { describe, expect, it } from 'vitest'
import fs from 'node:fs'
import { fileURLToPath } from 'node:url'

// Regresión (v0.41.2): en el PC de Diosvely, con 27 ficheros a la vez, tres tests rápidos superaron los 5 s por
// defecto (compare, glossary y sources) y la ejecución salía en rojo sin que hubiera ningún fallo real
describe('configuración de los tests', () => {
  const cfg = fs.readFileSync(fileURLToPath(new URL('../vite.config.js', import.meta.url)), 'utf8')
  it('margen por test de 30 s y la mitad de los núcleos', () => {
    expect(cfg).toMatch(/testTimeout: 30000/)
    expect(cfg).toMatch(/maxWorkers: '50%'/)
  })
})
