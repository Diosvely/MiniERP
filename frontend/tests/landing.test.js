import { describe, expect, it, vi } from 'vitest'
import es from '../src/i18n/es.js'
import en from '../src/i18n/en.js'
import { FEATURES, LINKEDIN, REPO, WHY, YOUTUBE, scrollToSection } from '../src/landing.js'

// v0.59.3 · Portada
describe('portada: enlaces del autor', () => {
  it('apuntan a GitHub, LinkedIn y YouTube de Diosvely, por https', () => {
    expect(REPO).toBe('https://github.com/Diosvely/MiniERP')
    expect(LINKEDIN).toBe('https://www.linkedin.com/in/diosvelyperezarteaga/')
    expect(YOUTUBE).toBe('https://www.youtube.com/@DiosvelyPerez')
  })
})

describe('portada: textos', () => {
  it('el lema es el elegido', () => {
    expect(es.landingTitle).toBe('Tu aliado en la contabilidad y el análisis financiero')
  })
  it('las 6 funciones y los puntos de «¿Por qué?» tienen título y texto en los dos idiomas', () => {
    expect(FEATURES).toHaveLength(6)
    for (const d of [es, en]) {
      for (const k of FEATURES) expect(d.landingFeature[k].title && d.landingFeature[k].text).toBeTruthy()
      for (const k of WHY) expect(d.landingWhy[k].title && d.landingWhy[k].text).toBeTruthy()
    }
  })
  it('la línea de confianza tiene los mismos puntos en español y en inglés', () => {
    expect(Array.isArray(es.landingTrust)).toBe(true)
    expect(en.landingTrust).toHaveLength(es.landingTrust.length)
  })
  it('la captura se presenta como datos ficticios, y la portada no habla de datos reales', () => {
    expect(es.landingShotCaption).toMatch(/datos ficticios/)
    expect(en.landingShotCaption).toMatch(/fictitious data/)
    const all = JSON.stringify([es.landingTitle, es.landingSubtitle, es.landingFeature, es.landingWhy, es.landingTrust])
    expect(all).not.toMatch(/datos reales/i)
  })
  it('no nombra ningún programa comercial (regla de contenido público)', () => {
    const all = JSON.stringify([es.landingFeature, en.landingFeature, es.landingWhy, en.landingWhy])
    expect(all).not.toMatch(/contasol|sage|a3\b|holded|sap\b/i)
  })
})

describe('portada: scrollToSection', () => {
  it('lleva a la sección y al primer campo sin cambiar el hash (la ruta)', () => {
    const focus = vi.fn(), scrollIntoView = vi.fn()
    const tabFocus = vi.fn()
    const el = { scrollIntoView, querySelector: (q) => (q === 'input' ? { focus } : { focus: tabFocus }) }
    const doc = { getElementById: (id) => (id === 'acceso' ? el : null) }
    globalThis.location = { hash: '#/' }
    expect(scrollToSection('acceso', doc)).toBe(true)
    expect(scrollIntoView).toHaveBeenCalled()
    expect(focus).toHaveBeenCalledWith({ preventScroll: true })   // el campo del correo, no la pestaña
    expect(tabFocus).not.toHaveBeenCalled()
    expect(globalThis.location.hash).toBe('#/')
  })
  it('si la sección no está (por ejemplo, en el glosario), no hace nada', () => {
    expect(scrollToSection('acceso', { getElementById: () => null })).toBe(false)
  })
})
