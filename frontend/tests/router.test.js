import { describe, it, expect } from 'vitest'
import { parseHash, companyPath } from '../src/router.js'

describe('rutas con almohadilla', () => {
  it('lista de empresas', () => {
    expect(parseHash('#/')).toEqual([])
    expect(parseHash('')).toEqual([])
  })
  it('empresa y pantalla', () => {
    expect(parseHash('#/empresa/abc-123/balance')).toEqual(['empresa', 'abc-123', 'balance'])
  })
  it('glosario', () => expect(parseHash('#/glosario')).toEqual(['glosario']))
  it('los enlaces de Supabase (#access_token=…) no son rutas de la app', () => {
    expect(parseHash('#access_token=xyz&type=recovery')).toEqual([])
  })
  it('companyPath construye la ruta y la de vuelta coincide', () => {
    expect(companyPath('abc', 'ratios')).toBe('/empresa/abc/ratios')
    expect(companyPath('abc')).toBe('/empresa/abc')
    expect(parseHash('#' + companyPath('a b', 'pyg'))).toEqual(['empresa', 'a b', 'pyg'])
  })
})
