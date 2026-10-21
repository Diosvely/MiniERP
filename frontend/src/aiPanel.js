// PANEL DE IA (v0.41.2): un botón abajo a la derecha abre un panel lateral con las IA de la app, como el chat de una
// web. Va aparte, sin React, para probarlo (tests/aiPanel.test.js).

// Pestañas del panel: el Tutor de asientos (en cualquier pantalla, si se puede escribir) y el Analista (solo cuando
// la pantalla abierta le pasa su ejercicio: el EFE y los Ratios)
export function panelTabs({ canWrite, topic }) {
  const tabs = []
  if (canWrite) tabs.push('tutor')
  tabs.push('analyst')
  return tabs.map((id) => ({ id, ready: id === 'tutor' || topic?.kind === 'analyst' }))
}

// La pestaña que se abre: la que pide la pantalla (botón «Interpretar con el Analista»), o el Analista si la pantalla
// lo tiene, o el Tutor
export function defaultTab({ canWrite, topic, asked }) {
  if (asked) return asked
  if (topic?.kind === 'analyst') return 'analyst'
  return canWrite ? 'tutor' : 'analyst'
}

// Conversación del Tutor: se guardan las últimas 20 preguntas (solo en esta pestaña del navegador, nunca en la base
// de datos: lo que escribes puede llevar nombres de terceros)
export const MAX_MESSAGES = 20
export const addMessage = (msgs, msg) => [...msgs, msg].slice(-MAX_MESSAGES)
export const updateMessage = (msgs, id, patch) => msgs.map((m) => (m.id === id ? { ...m, ...patch } : m))

// Enter envía la pregunta; Mayús + Enter hace un salto de línea
export const sendsOnKey = (e) => e.key === 'Enter' && !e.shiftKey && !e.isComposing
