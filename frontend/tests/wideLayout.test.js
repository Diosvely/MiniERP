import { describe, expect, it } from 'vitest'
import fs from 'node:fs'
import { fileURLToPath } from 'node:url'
import { pairHalves } from '../src/wideLayout'

const css = fs.readFileSync(fileURLToPath(new URL('../src/index.css', import.meta.url)), 'utf8')

describe('pantalla ancha (v0.41.1)', () => {
  it('empareja las tarjetas pequeñas de dos en dos, en orden; una sin pareja va a todo el ancho', () => {
    expect(pairHalves([true, true, false, true, true, true])).toEqual([true, true, false, true, true, false])
    expect(pairHalves([true, false, true])).toEqual([false, false, false])
    expect(pairHalves([false, true, true, true, true])).toEqual([false, true, true, true, true])
    expect(pairHalves([])).toEqual([])
    expect(pairHalves([true])).toEqual([false])
  })
  it('en el PC se usa el ancho hasta 1600 px, y las tarjetas emparejadas van en dos columnas desde 1320 px', () => {
    expect(css).toMatch(/main:has\(\.empresa-layout\) \{ max-width: 1600px; \}/)
    expect(css).toMatch(/@media \(min-width: 1320px\) \{\s*\.empresa-contenido \{ display: grid; grid-template-columns: repeat\(2, minmax\(0, 1fr\)\)/)
    expect(css).toMatch(/\.empresa-contenido > \.mitad \{ grid-column: auto; \}/)
  })
  // Regresión (paso 215, visto por Diosvely en Inmovilizado, modo Auditor): con el menú más alto que el contenido, la
  // rejilla estiraba la fila de la ruta hasta igualarlo y las tarjetas empezaban 360 px más abajo
  it('las filas de la rejilla no se estiran hasta la altura del menú (align-content: start)', () => {
    expect(css).toMatch(/\.empresa-contenido \{ display: grid;[^}]*align-content: start;/)
  })
  it('en el PC la letra baja a 14 px y los rellenos se ajustan; el móvil y la impresión no cambian', () => {
    expect(css).toMatch(/@media screen and \(min-width: 900px\) \{\s*html \{ font-size: 14px; \}/)
  })
  // Regresión: en el móvil, el desplegable de territorio de Terceros (y la fecha de Asientos) desbordaban la pantalla
  // 90 px porque la rejilla usaba «1fr» (que no baja del ancho mínimo de su contenido)
  it('la rejilla de cabecera no desborda en el móvil (minmax(0, 1fr))', () => {
    expect(css).toMatch(/\.rejilla-cabecera \{ display: grid; grid-template-columns: repeat\(2, minmax\(0, 1fr\)\)/)
  })
})
