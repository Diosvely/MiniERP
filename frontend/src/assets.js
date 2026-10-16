// INMOVILIZADO (v0.35.0): cálculos de la pantalla. Quien decide y contabiliza es la base de datos (0041); aquí solo se
// prepara lo que se le envía y se enseña antes: el % anual, el aviso fiscal y la vista previa de la amortización.

const cents = (v) => Math.round((parseFloat(String(v ?? '').replace(',', '.')) || 0) * 100)
export { cents }

// % anual de una vida útil en meses (48 meses → 25 %)
export const annualPct = (months) => (Number(months) > 0 ? Math.round(120000 / Number(months)) / 100 : 0)

// Avisos fiscales (art. 12.1.a LIS): coeficiente por encima del máximo o vida por encima del período máximo
//   cls: fila de depreciation_classes { max_pct, max_years } · months: vida útil contable
export function taxWarnings(cls, months) {
  if (!cls || !(Number(months) > 0)) return []
  const out = []
  const rate = annualPct(months)
  if (rate > Number(cls.max_pct)) out.push({ code: 'above_tax_max', rate, max: Number(cls.max_pct) })
  if (Number(months) > Number(cls.max_years) * 12) out.push({ code: 'below_tax_min', years: Math.round(Number(months) / 1.2) / 10, maxYears: Number(cls.max_years) })
  return out
}

// Fechas ISO sin husos horarios (yyyy-mm-dd)
const parse = (iso) => { const [y, m, d] = String(iso).slice(0, 10).split('-').map(Number); return { y, m, d } }
const iso = (y, m, d) => `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`
const daysIn = (y, m) => new Date(Date.UTC(y, m, 0)).getUTCDate()
// Sumar meses como PostgreSQL: el día se queda en el último del mes si no existe (31/01 + 1 mes = 28/02)
export function addMonths(isoDate, n) {
  const { y, m, d } = parse(isoDate)
  const t = y * 12 + (m - 1) + n
  const ny = Math.floor(t / 12), nm = (t % 12) + 1
  return iso(ny, nm, Math.min(d, daysIn(ny, nm)))
}
const dayNo = (isoDate) => { const { y, m, d } = parse(isoDate); return Date.UTC(y, m - 1, d) / 86400000 }
const nextDay = (isoDate) => { const dt = new Date((dayNo(isoDate) + 1) * 86400000); return dt.toISOString().slice(0, 10) }

// Amortización acumulada a una fecha: lineal por meses, el primer mes por días (la misma regla que
// erp.asset_accumulated_at). Para la vista previa: lo que cuenta es lo que calcula la base de datos.
export function accumulatedAt(cost, residual, months, start, date) {
  if (!start || !date || date < start || !(Number(months) > 0)) return 0
  const base = cents(cost) - cents(residual)
  const d1 = nextDay(date)
  let full = 0
  while (addMonths(start, full + 1) <= d1) full++
  const from = addMonths(start, full), to = addMonths(start, full + 1)
  const fraction = full + (dayNo(d1) - dayNo(from)) / (dayNo(to) - dayNo(from))
  return Math.min(base, Math.round(base * fraction / Number(months))) / 100
}

// Último día del mes de una fecha (la amortización se suele contabilizar a fin de mes)
export function endOfMonth(isoDate) {
  const { y, m } = parse(isoDate)
  return iso(y, m, daysIn(y, m))
}

// Cuentas de activo amortizable: 20x / 21x / 22x salvo los terrenos (210, 220)
export const isAssetAccount = (no) => /^2[012]/.test(String(no ?? '')) && !/^2[12]0/.test(String(no))

// Líneas de facturas que pueden ser un activo
//   purchase: las de facturas recibidas a una cuenta 2x que aún no tienen ficha (alta)
//   sale: las de facturas emitidas a la cuenta del activo que aún no se han usado en una baja (venta)
//   lines: invoice_lines { invoice_id, line_no, amount, sign, gl_account_id } · accounts: { id, account_no, name }
//   invoices: v_invoices · used: ids de facturas ya usadas
export function invoiceAssetLines(lines, accounts, invoices, type, used = new Set(), accountNo = null) {
  const acc = new Map(accounts.map((a) => [a.id, a]))
  const inv = new Map(invoices.filter((i) => i.invoice_type === type && i.document_kind === 'invoice').map((i) => [i.id, i]))
  return lines
    .map((l) => ({ l, a: acc.get(l.gl_account_id), i: inv.get(l.invoice_id) }))
    .filter(({ a, i }) => a && i && isAssetAccount(a.account_no) && !used.has(i.id) && (!accountNo || a.account_no === accountNo))
    .map(({ l, a, i }) => ({ key: `${i.id}/${l.line_no}`, invoice_id: i.id, invoice_no: i.external_document_no || i.invoice_no,
                             partner_name: i.partner_name, date: i.invoice_date, account_no: a.account_no, account_name: a.name,
                             amount: Number(l.amount) * Number(l.sign ?? 1), description: l.description ?? i.description }))
    .sort((x, y) => (x.date < y.date ? 1 : x.date > y.date ? -1 : x.key.localeCompare(y.key)))
}

// Clases fiscales: primero las del grupo del PGC de la cuenta elegida (217 → equipos informáticos)
export function classesFor(classes, accountNo) {
  const p = String(accountNo ?? '').slice(0, 3)
  return [...classes].sort((a, b) => (b.pgc_prefix === p) - (a.pgc_prefix === p) || a.sort - b.sort)
}

// Totales de la lista: coste, amortización acumulada y valor neto contable de los activos en uso
export function assetTotals(assets) {
  const live = assets.filter((a) => a.status === 'active')
  const sum = (k) => live.reduce((s, a) => s + cents(a[k]), 0) / 100
  return { count: live.length, cost: sum('cost'), accumulated: sum('accumulated'), net: sum('net_book_value') }
}
