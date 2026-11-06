import { describe, expect, it } from 'vitest'
import es from '../src/i18n/es.js'
import en from '../src/i18n/en.js'
import { BALANCE_MODELS, DEFAULT_MODEL, modelFor, modelSource, readModel, saveModel } from '../src/balanceModels.js'
import { SOURCES } from '../src/sources.js'

// v0.60.0 · El Balance en los tres modelos del PGC
const memory = () => { const m = new Map(); return { getItem: (k) => m.get(k) ?? null, setItem: (k, v) => m.set(k, v) } }

describe('modelos del Balance', () => {
  it('son PYMES, abreviado y normal, y por defecto PYMES', () => {
    expect(BALANCE_MODELS.map((m) => m.code)).toEqual(['pymes', 'abreviado', 'normal'])
    expect(DEFAULT_MODEL).toBe('pymes')
    expect(readModel(memory())).toBe('pymes')
  })
  it('recuerda el último elegido, e ignora un valor raro', () => {
    const s = memory()
    saveModel('normal', s)
    expect(readModel(s)).toBe('normal')
    saveModel('sectorial', s)
    expect(readModel(s)).toBe('normal')
    s.setItem('balanceModel', 'otro')
    expect(readModel(s)).toBe('pymes')
  })
  it('sin almacenamiento (modo privado) no falla y usa PYMES', () => {
    const roto = { getItem: () => { throw new Error('bloqueado') }, setItem: () => { throw new Error('bloqueado') } }
    expect(readModel(roto)).toBe('pymes')
    expect(() => saveModel('normal', roto)).not.toThrow()
  })
  it('la PyG siempre va en PYMES', () => {
    expect(modelFor('pyg', 'normal')).toBe('pymes')
    expect(modelFor('balance', 'normal')).toBe('normal')
    expect(modelFor('balance', undefined)).toBe('pymes')
  })
  it('cada modelo tiene su fuente en la base documental y sus textos en los dos idiomas', () => {
    for (const { code } of BALANCE_MODELS) {
      expect(SOURCES[modelSource(code)]).toBeDefined()
      for (const d of [es, en]) {
        expect(d.fsModel[code]).toBeTruthy()
        expect(d.fsModel.norm[code]).toBeTruthy()
      }
    }
    expect(SOURCES.pgcpymes.url).toContain('/rd/2007/11/16/1515/')
    expect(SOURCES.pgcmodelos.url).toContain('/rd/2007/11/16/1514/')
  })
  it('la ayuda del Balance ya no dice que es solo el modelo PYMES', () => {
    expect(es.balanceSheetHelp).not.toMatch(/Modelo PYMES/)
  })
})
