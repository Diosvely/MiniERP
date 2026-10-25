// SUBVENCIONES Y ECPN (v0.44.0): cómo se enseña lo que hace la base de datos (0064 y 0065). Las reglas (NRV 18.ª y
// 13.ª), la imputación con la amortización y el ECPN los calcula la base de datos; aquí se preparan los datos y se
// dibujan los mismos asientos antes de contabilizar (tests/grants.test.js los compara con los supuestos S1 a S4).
import { parseAmount } from './practice'

export const KINDS = ['capital', 'operating']

export const emptyForm = (date = '') => ({
  kind: 'capital', description: '', grantor: '', amount: '', date, refundable: false, condition_due: '', collected: false,
  asset_id: '', tax_rate: '25',
})

const num = (v) => (String(v ?? '').trim() === '' ? undefined : parseAmount(v))
const r2 = (v) => Math.round((Number(v) || 0) * 100) / 100
const L = (account, debit, credit) => ({ account, debit: r2(debit), credit: r2(credit) })
const clean = (lines) => lines.filter((l) => l.debit || l.credit)

// Lo que se manda a erp.grant_create (los vacíos no se mandan)
export function payload(form, companyId) {
  const p = { company_id: companyId, kind: form.kind, date: form.date, refundable: Boolean(form.refundable), collected: Boolean(form.collected) }
  const set = (k, v) => { if (v !== undefined && v !== '' && !Number.isNaN(v)) p[k] = v }
  set('description', String(form.description ?? '').trim())
  set('grantor', String(form.grantor ?? '').trim())
  set('amount', num(form.amount))
  set('tax_rate', num(form.tax_rate))
  if (form.refundable) set('condition_due', form.condition_due)
  if (form.kind === 'capital') set('asset_id', form.asset_id)
  return p
}

// ¿La condición vence en los 12 meses siguientes? (deuda a corto, 522; si no, 172)
export function shortTerm(date, due) {
  if (!date || !due) return true
  const limit = `${Number(date.slice(0, 4)) + 1}${date.slice(4)}`
  return due <= limit
}

// Asiento de la concesión: 4708 (o el banco, si ya está cobrada) / 940 (capital) · 740 (explotación) · 522 / 172
// (reintegrable) + el efecto impositivo de la de capital no reintegrable (8301 / 479)
export function concessionEntry(form) {
  const amount = num(form.amount) ?? 0
  if (amount <= 0) return []
  const first = form.collected ? '572' : form.kind === 'capital' ? '4708' : '47089'
  const credit = form.refundable ? (shortTerm(form.date, form.condition_due) ? '522' : '172') : form.kind === 'capital' ? '940' : '740'
  const tax = form.kind === 'capital' && !form.refundable ? r2(amount * (num(form.tax_rate) ?? 25) / 100) : 0
  return clean([L(first, amount, 0), L(credit, 0, amount), L('8301', tax, 0), L('479', 0, tax)])
}

// Se cumple la condición: 522 / 172 → 940 (capital, con su efecto impositivo) o 740 (explotación)
export function unconditionalEntry(g) {
  if (!g) return []
  const debt = shortTerm(g.grant_date, g.condition_due) ? '522' : '172'
  const tax = g.kind === 'capital' ? r2(Number(g.amount) * Number(g.tax_rate) / 100) : 0
  return clean([L(debt, g.amount, 0), L(g.kind === 'capital' ? '940' : '740', 0, g.amount), L('8301', tax, 0), L('479', 0, tax)])
}

// Imputación del cierre (o lo que queda, al dar de baja el activo): 840 / 746 y 479 / 8301
export const imputationEntry = (amount, tax) => clean([L('840', amount, 0), L('746', 0, amount), L('479', tax, 0), L('8301', 0, tax)])

// Qué parte del coste del activo financia la subvención (%): ese % de cada amortización pasa a resultados
export const assetShare = (amount, cost) => (Number(cost) > 0 ? Math.round((num(amount) ?? 0) / Number(cost) * 10000) / 100 : 0)

// El movimiento que se puede deshacer: el último contabilizado
export function undoable(events = []) {
  return [...events].filter((e) => e.status === 'posted').sort((a, b) => Number(b.seq) - Number(a.seq))[0]?.id ?? null
}

export const balanced = (lines) => lines.reduce((s, l) => s + Math.round(l.debit * 100) - Math.round(l.credit * 100), 0) === 0

// ---------- ECPN ----------
// Parte A: [{ key, amount, level }] en el orden del modelo del PGC (las de nivel 0 son totales)
export const PART_A = [['result', 0], ['b_grants', 1], ['b_tax', 1], ['b_other', 1], ['b_total', 0], ['c_grants', 1], ['c_tax', 1], ['c_total', 0], ['total', 0]]
export function partA(a = {}) {
  return PART_A.filter(([k]) => k !== 'b_other' || Number(a.b_other)).map(([key, level]) => ({ key, level, amount: Number(a[key] ?? 0) }))
}

// Parte B: filas (saldo inicial, ingresos y gastos reconocidos, operaciones con socios, otras variaciones, saldo final)
// × columnas (las que tienen movimientos) con su total
export const PART_B_ROWS = ['start', 'recognised', 'owners', 'other']
export function partB(data) {
  const cols = data?.columns ?? []
  const b = data?.part_b ?? {}
  const rows = PART_B_ROWS.map((key) => {
    const values = Object.fromEntries(cols.map((c) => [c, Number(b[key]?.[c] ?? 0)]))
    return { key, values, total: r2(cols.reduce((s, c) => s + values[c], 0)) }
  })
  const end = Object.fromEntries(cols.map((c) => [c, r2(rows.reduce((s, r) => s + r.values[c], 0))]))
  rows.push({ key: 'end', values: end, total: r2(cols.reduce((s, c) => s + end[c], 0)) })
  return { cols, rows }
}

// Signo de las cuentas anuales: las cifras negativas entre paréntesis
export const paren = (v, fmt) => (Number(v) < 0 ? `(${fmt(-v)})` : fmt(v))
