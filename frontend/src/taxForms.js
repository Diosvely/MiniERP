// MODELOS (v0.39.0): cómo se enseñan las casillas que calcula la base de datos (0051 y 0052)
import { cents } from './assets'

export const SECTIONS = ['devengado', 'deducible', 'resultado', 'informacion', 'volumen']

// Casillas agrupadas por apartado, en el orden del modelo
export function groupBoxes(rows) {
  return SECTIONS.map((section) => ({ section, rows: rows.filter((r) => r.section === section) })).filter((g) => g.rows.length > 0)
}

// Casilla del resultado final de cada modelo
export const RESULT_BOX = { 303: '71', 420: '45', 390: '86', 425: '115' }

// Resultado del modelo: a ingresar, a compensar o devolver, o cero
export function formResult(form, rows) {
  const r = rows.find((x) => x.box === RESULT_BOX[form])
  if (!r) return null
  const amount = Number(r.amount)
  return { box: r.box, amount, outcome: amount > 0 ? 'pay' : amount < 0 ? 'credit' : 'zero' }
}

// Modelo 347: totales de ventas (B) y compras (A) y terceros sin NIF
export function totals347(rows) {
  const sum = (k) => rows.filter((r) => r.op_key === k).reduce((s, r) => s + cents(r.total), 0) / 100
  return { sales: sum('B'), purchases: sum('A'), count: rows.length, missing: rows.filter((r) => r.missing_vat_no).length }
}

// Modelo 349: operaciones del periodo, rectificaciones y total por clave
export function group349(rows) {
  const operations = rows.filter((r) => r.section === 'operation')
  const rectifications = rows.filter((r) => r.section === 'rectification')
  const byKey = {}
  for (const r of operations) byKey[r.op_key] = (byKey[r.op_key] ?? 0) + cents(r.amount)
  for (const k of Object.keys(byKey)) byKey[k] /= 100
  return { operations, rectifications, byKey }
}
