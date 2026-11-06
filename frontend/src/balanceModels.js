// v0.60.0 · El Balance en los tres modelos del PGC (ADR 0062, migración 0089).
//   pymes     → RD 1515/2007 (el de siempre, por defecto)
//   abreviado → RD 1514/2007, modelo abreviado
//   normal    → RD 1514/2007, modelo normal (el de la foto del BOE)
// Es el mismo balance: la base de datos calcula el saldo de cada cuenta una vez y solo la recoloca en su partida.
export const BALANCE_MODELS = [
  { code: 'pymes', source: 'pgcpymes' },
  { code: 'abreviado', source: 'pgcmodelos' },
  { code: 'normal', source: 'pgcmodelos' },
]
export const DEFAULT_MODEL = 'pymes'
const KEY = 'balanceModel'

export const isModel = (code) => BALANCE_MODELS.some((m) => m.code === code)
export const modelSource = (code) => (BALANCE_MODELS.find((m) => m.code === code) ?? BALANCE_MODELS[0]).source

// El último modelo elegido en este navegador (decisión 2). Sin almacenamiento, o con un valor raro: PYMES.
export function readModel(storage = globalThis.localStorage) {
  try {
    const v = storage?.getItem(KEY)
    return isModel(v) ? v : DEFAULT_MODEL
  } catch {
    return DEFAULT_MODEL
  }
}
export function saveModel(code, storage = globalThis.localStorage) {
  try { if (isModel(code)) storage?.setItem(KEY, code) } catch { /* modo privado: no se recuerda */ }
}

// El modelo solo existe para el Balance: la PyG sigue en PYMES (decisión 4)
export const modelFor = (statement, model) => (statement === 'balance' && isModel(model) ? model : DEFAULT_MODEL)
