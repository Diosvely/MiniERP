import { describe, it, expect } from 'vitest'
import { money, accountName, taxLabel } from '../src/format.js'
import { tEs, tEn } from './helpers.js'

describe('money · importes con formato de cada idioma', () => {
  it('español: punto de miles y coma decimal, también con 4 cifras', () => {
    expect(money(1234.5, 'es')).toBe('1.234,50')
    expect(money(2900, 'es')).toBe('2.900,00')          // Intl no agrupa 4 cifras en español: useGrouping 'always'
  })
  it('inglés: coma de miles y punto decimal', () => {
    expect(money(1234.5, 'en')).toBe('1,234.50')
  })
  it('negativos, texto numérico y valores vacíos', () => {
    expect(money(-50, 'es')).toBe('-50,00')
    expect(money('1210', 'es')).toBe('1.210,00')
    expect(money(null, 'es')).toBe('0,00')
    expect(money('abc', 'es')).toBe('0,00')
  })
})

describe('accountName · nombre de la cuenta en el idioma elegido', () => {
  const a = { name: 'Bancos', name_en: 'Banks' }
  it('usa la traducción en inglés si existe', () => expect(accountName(a, 'en')).toBe('Banks'))
  it('en español, siempre el nombre oficial', () => expect(accountName(a, 'es')).toBe('Bancos'))
  it('sin traducción, el nombre oficial', () => expect(accountName({ name: 'Caja', name_en: null }, 'en')).toBe('Caja'))
})

describe('taxLabel · nombre corto de un tipo de impuesto', () => {
  it('tipo general con su porcentaje', () => {
    expect(taxLabel({ tax_type: 'VAT', rate_pct: 21, rate_category: 'general' }, tEs, 'es')).toMatch(/21 %/)
  })
  it('inversión del sujeto pasivo: lo indica', () => {
    const l = taxLabel({ tax_type: 'VAT', rate_pct: 21, rate_category: 'reverse_charge' }, tEs, 'es')
    expect(l).toMatch(/21 %/)
    expect(l).toContain(tEs('taxCategory.reverse_charge'))
  })
  it('exenta: muestra la causa y la clave en lugar del 0 %', () => {
    const l = taxLabel({ tax_type: 'VAT', rate_pct: 0, rate_category: 'export', exemption_key: 'E2' }, tEn, 'en')
    expect(l).toContain('(E2)')
    expect(l).not.toMatch(/0 %/)
  })
})
