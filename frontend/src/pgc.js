import { GLOSSARY } from './glossary'

// PGC DE ESTUDIO (v0.48.0): un libro de consulta del Plan General de Contabilidad, de solo lectura y común a todas las
// empresas (migración 0071). Aquí, lo que no es pantalla: cargar los datos una vez, encontrar la ficha de una cuenta,
// el buscador y los enlaces automáticos entre cuentas (la carga, en pgcLoad.js). Lo usan la pantalla #/pgc y el panel de Nuevo asiento.

// Índices en memoria: cuentas ordenadas, fichas por código y, por cada NRV, las fichas que la citan
export function buildPgc({ groups = [], subgroups = [], accounts = [], cards = [], rules = [], principles = [] }) {
  const byCode = (rows, key) => Object.fromEntries(rows.map((r) => [r[key], r]))
  const list = [...accounts].sort((x, y) => x.account.localeCompare(y.account))
  const cardMap = byCode(cards, 'code')
  const nrvRefs = {}
  for (const c of [...cards].sort((x, y) => x.code.localeCompare(y.code))) {
    for (const n of c.nrv ?? []) (nrvRefs[n] ??= []).push(c.code)
  }
  return { groups: byCode(groups, 'grp'), subgroups: byCode(subgroups, 'subgroup'), accounts: list, accountMap: byCode(list, 'account'),
    cards: cardMap, rules, principles, nrvRefs }
}

// Una ficha puede ser de 3 dígitos (vale para toda la cuenta) o de 4 (específica): 4009 → 4009, 4000 → 400, 4720 → 472
export function cardKey(account, cards) {
  if (!account) return null
  if (cards[account]) return account
  const three = account.slice(0, 3)
  return cards[three] ? three : null
}

// La primera cuenta de 4 dígitos que empieza por un código: 640 → 6400 · 4751 → 4751 · 8 dígitos → sus 4 primeros
export function firstAccount(code, accounts) {
  const c = String(code ?? '').replace(/\D/g, '').slice(0, 4)
  if (c.length < 3) return null
  return accounts.find((a) => a.account.startsWith(c))?.account ?? null
}

// En Nuevo asiento: la cuenta del PGC de una subcuenta (sus 4 primeros dígitos) · 47200007 → 4720 · 57 → nada
export const pgcCodeOf = (no) => (/^\d{3}/.test(String(no ?? '').trim()) ? String(no).trim().slice(0, 4) : null)

// Sin tildes ni mayúsculas: «credito» encuentra «crédito»
export const norm = (s) => String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()

// Buscador: el número empieza por el texto o el nombre lo contiene; con el grupo (1 a 9) y «solo con ficha»
export function filterAccounts(accounts, cards, { text = '', group = '', onlyCards = false } = {}) {
  const q = norm(text).trim()
  return accounts.filter((a) => (!group || a.account[0] === group)
    && (!onlyCards || cardKey(a.account, cards))
    && (!q || a.account.startsWith(q) || norm(a.name).includes(q)))
}

// Enlaces automáticos en los textos: «contra la 610» → enlace a la 6100; «la 4751» → 4751; «cuenta 640» → 6400.
// Devuelve trozos { text } y { text, go } para pintarlos sin HTML (React escapa el texto)
const REF = /\b(cuentas?|la|las|de la|en la|contra la|a la|desde la)\s+(\d{3,4})\b/g
export function linkify(text, accounts) {
  const out = []
  let last = 0
  for (const m of String(text ?? '').matchAll(REF)) {
    const go = firstAccount(m[2], accounts)
    if (!go) continue
    const at = m.index + m[0].length - m[2].length
    if (at > last) out.push({ text: text.slice(last, at) })
    out.push({ text: m[2], go })
    last = at + m[2].length
  }
  if (last < String(text ?? '').length) out.push({ text: text.slice(last) })
  return out
}

// Sumas del asiento de ejemplo
export function exampleTotals(lines) {
  const sum = (k) => Math.round((lines ?? []).reduce((s, l) => s + Number(l[k] || 0), 0) * 100) / 100
  return { debit: sum('debe'), credit: sum('haber') }
}

// Términos del glosario relacionados con la cuenta (por sus cuentas del PGC): la 4720 → «IVA soportado»…
export function glossaryFor(account) {
  if (!account) return []
  return Object.entries(GLOSSARY).filter(([, g]) => (g.pgc ?? []).some((p) => account.startsWith(p))).map(([id]) => id)
}

// Rutas: #/pgc · #/pgc/4000 · #/pgc/nrv · #/pgc/nrv/12 · #/pgc/principios
export const DEFAULT_ACCOUNT = '4000'
export function pgcRoute(parts = []) {
  const [a, b] = parts
  if (a === 'nrv') return { tab: 'nrv', nrv: Number(b) || null }
  if (a === 'principios') return { tab: 'principles' }
  return { tab: 'accounts', account: /^\d{3,8}$/.test(a ?? '') ? a : null }
}
export const pgcPath = (account) => `/pgc/${account}`
export const nrvPath = (n) => `/pgc/nrv${n ? `/${n}` : ''}`

// «NRV 12.ª»
export const nrvLabel = (n) => `NRV ${n}.ª`
