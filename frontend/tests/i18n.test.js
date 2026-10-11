import { describe, it, expect } from 'vitest'
import es from '../src/i18n/es.js'
import en from '../src/i18n/en.js'
import { GLOSSARY, SECTION_TERM } from '../src/glossary.js'
import { TEMPLATES } from '../src/templates.js'

// Todas las claves "a.b.c" de un diccionario
const keys = (o, p = '') => Object.entries(o).flatMap(([k, v]) => (v && typeof v === 'object' ? keys(v, `${p}${k}.`) : [`${p}${k}`]))
// err.word.* son palabras que solo hay que traducir al español (credit → acreedor): en inglés no hacen falta
const ONLY_ES = /^err\.word\./

describe('idiomas · español e inglés tienen los mismos textos', () => {
  it('ninguna clave falta en inglés', () => {
    const e = new Set(keys(en))
    expect(keys(es).filter((k) => !e.has(k) && !ONLY_ES.test(k))).toEqual([])
  })
  it('ninguna clave falta en español', () => {
    const s = new Set(keys(es))
    expect(keys(en).filter((k) => !s.has(k))).toEqual([])
  })
  it('ningún texto vacío', () => {
    const empty = (d) => keys(d).filter((k) => k.split('.').reduce((o, p) => o[p], d) === '' && !k.endsWith('.sub') && !k.endsWith('.hint'))
    expect(empty(es)).toEqual([])
    expect(empty(en)).toEqual([])
  })
})

describe('glosario', () => {
  it('al menos 25 términos, todos en los dos idiomas y con su nombre en BC y SAP', () => {
    const all = Object.values(GLOSSARY)
    expect(all.length).toBeGreaterThanOrEqual(25)
    for (const g of all) {
      expect(g.es.term && g.es.def && g.en.term && g.en.def).toBeTruthy()
      expect(g.bc && g.sap).toBeTruthy()
    }
  })
  it('cada pantalla apunta a un término que existe', () => {
    for (const id of Object.values(SECTION_TERM)) expect(GLOSSARY[id], id).toBeDefined()
  })
})

describe('plantillas de asientos', () => {
  it('cada una tiene texto en los dos idiomas, un total y prefijos del PGC válidos', () => {
    for (const tpl of TEMPLATES) {
      expect(es.tpl[tpl.id].label && en.tpl[tpl.id].label, tpl.id).toBeTruthy()
      expect(tpl.lines.filter((l) => l.total)).toHaveLength(1)
      for (const l of tpl.lines) {
        expect(l.prefix).toMatch(/^[1-7]\d{2,3}$/)
        expect(['debit', 'credit']).toContain(l.side)
      }
      // Partida doble: hay al menos una línea al Debe y otra al Haber
      expect(new Set(tpl.lines.map((l) => l.side)).size).toBe(2)
    }
  })
})
