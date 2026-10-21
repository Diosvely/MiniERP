import { describe, expect, it } from 'vitest'
import { groupForSection, nextIndex, toggleGroup } from '../src/menuAccordion'
import es from '../src/i18n/es.js'
import en from '../src/i18n/en.js'

describe('menú en acordeón (v0.41.1)', () => {
  it('pulsar un área la abre sola; pulsar la abierta la cierra', () => {
    expect(toggleGroup('menuAccounting', 'menuReports')).toBe('menuReports')
    expect(toggleGroup('menuReports', 'menuReports')).toBe(null)
    expect(toggleGroup(null, 'menuCompany')).toBe('menuCompany')
  })
  it('al entrar en una pantalla se abre su área; el Inicio deja la que hubiera', () => {
    expect(groupForSection('menuTaxes', 'menuAccounting')).toBe('menuTaxes')
    expect(groupForSection('', 'menuReports')).toBe('menuReports')
    expect(groupForSection(undefined, null)).toBe(null)
  })
  it('las flechas recorren los botones del menú dando la vuelta', () => {
    expect(nextIndex(0, 5, 'ArrowDown')).toBe(1)
    expect(nextIndex(4, 5, 'ArrowDown')).toBe(0)
    expect(nextIndex(0, 5, 'ArrowUp')).toBe(4)
    expect(nextIndex(-1, 5, 'ArrowDown')).toBe(0)
    expect(nextIndex(3, 5, 'Home')).toBe(0)
    expect(nextIndex(1, 5, 'End')).toBe(4)
    expect(nextIndex(2, 0, 'ArrowDown')).toBe(-1)
  })
  it('el área «Empresa» (publicar como demo, borrar) tiene nombre en los dos idiomas', () => {
    expect(es.menuCompany).toBe('Empresa')
    expect(en.menuCompany).toBe('Company')
  })
})
