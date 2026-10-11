// Utilidades comunes de los tests
import es from '../src/i18n/es.js'
import en from '../src/i18n/en.js'

// Traductor igual que el de la app (useI18n), sin React
export const makeT = (dict) => (key) => key.split('.').reduce((o, p) => o?.[p], dict) ?? key
export const tEs = makeT(es)
export const tEn = makeT(en)

// "Fichero" en memoria con la misma interfaz que el File del navegador
export const fakeFile = (name, content) => {
  const buf = typeof content === 'string' ? new TextEncoder().encode(content) : content
  return { name, arrayBuffer: async () => buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength) }
}
