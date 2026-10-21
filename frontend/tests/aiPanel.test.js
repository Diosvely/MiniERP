import { describe, expect, it } from 'vitest'
import { MAX_MESSAGES, addMessage, defaultTab, panelTabs, sendsOnKey, updateMessage } from '../src/aiPanel'
import es from '../src/i18n/es.js'
import en from '../src/i18n/en.js'

describe('panel de IA (v0.41.2)', () => {
  it('pestañas: el Tutor si se puede escribir; el Analista siempre, listo solo si la pantalla le pasa su ejercicio', () => {
    expect(panelTabs({ canWrite: true, topic: null })).toEqual([{ id: 'tutor', ready: true }, { id: 'analyst', ready: false }])
    expect(panelTabs({ canWrite: true, topic: { kind: 'analyst', year: 2026 } })[1]).toEqual({ id: 'analyst', ready: true })
    expect(panelTabs({ canWrite: false, topic: null }).map((x) => x.id)).toEqual(['analyst'])
  })
  it('pestaña al abrir: la pedida; si no, el Analista en el EFE / Ratios; si no, el Tutor', () => {
    expect(defaultTab({ canWrite: true, topic: { kind: 'analyst', year: 2026 }, asked: 'tutor' })).toBe('tutor')
    expect(defaultTab({ canWrite: true, topic: { kind: 'analyst', year: 2026 }, asked: null })).toBe('analyst')
    expect(defaultTab({ canWrite: true, topic: null, asked: null })).toBe('tutor')
    expect(defaultTab({ canWrite: false, topic: null, asked: null })).toBe('analyst')
  })
  it('la conversación guarda las últimas 20 preguntas y actualiza la respuesta de cada una', () => {
    let m = []
    for (let i = 1; i <= 25; i++) m = addMessage(m, { id: i, text: `p${i}` })
    expect(m).toHaveLength(MAX_MESSAGES)
    expect(m[0].id).toBe(6)
    m = updateMessage(m, 25, { result: { ok: true } })
    expect(m.at(-1)).toEqual({ id: 25, text: 'p25', result: { ok: true } })
    expect(m[0]).toEqual({ id: 6, text: 'p6' })
  })
  it('Enter envía; Mayús + Enter y la escritura con acentos compuestos no', () => {
    expect(sendsOnKey({ key: 'Enter', shiftKey: false })).toBe(true)
    expect(sendsOnKey({ key: 'Enter', shiftKey: true })).toBe(false)
    expect(sendsOnKey({ key: 'Enter', shiftKey: false, isComposing: true })).toBe(false)
    expect(sendsOnKey({ key: 'a', shiftKey: false })).toBe(false)
  })
  it('textos en los dos idiomas', () => {
    for (const k of ['aiPanelButton', 'aiPanelTitle', 'aiPanelClose', 'aiPanelAsk', 'aiPanelAskAnalyst', 'aiPanelYear', 'tutorLoadedPanel', 'aiYou']) {
      expect(es[k], k).toBeTruthy()
      expect(en[k], k).toBeTruthy()
    }
  })
})
