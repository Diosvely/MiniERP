// COBROS Y PAGOS (v0.32.0): cálculos de la pantalla. Quien decide es la base de datos (erp.post_payment, 0035);
// aquí solo se prepara lo que se le envía y se enseña antes de contabilizar.

const cents = (v) => Math.round((parseFloat(String(v ?? '').replace(',', '.')) || 0) * 100)
export { cents }

// Terceros con facturas pendientes de un tipo (purchase → pagos · sale → cobros), con su total y su factura más vencida
export function partnersWithPending(items, invoiceType) {
  const map = new Map()
  for (const i of items) {
    if (i.invoice_type !== invoiceType || Number(i.pending) <= 0) continue
    const p = map.get(i.partner_id) ?? { partner_id: i.partner_id, name: i.partner_name, account_no: i.partner_account_no,
                                         pending: 0, invoices: 0, maxOverdue: 0 }
    p.pending = (Math.round(p.pending * 100) + cents(i.pending)) / 100
    p.invoices += 1
    p.maxOverdue = Math.max(p.maxOverdue, Number(i.days_overdue ?? 0))
    map.set(i.partner_id, p)
  }
  return [...map.values()].sort((a, b) => b.maxOverdue - a.maxOverdue || b.pending - a.pending || a.name.localeCompare(b.name))
}

// Facturas elegidas → lo que se envía (importes en euros con 2 decimales) y los errores que verá el usuario antes
//   selected: { [invoice_id]: '123,45' }  · items: partidas abiertas del tercero
export function buildApplications(selected, items) {
  const apps = []
  const errors = []
  for (const i of items) {
    if (!(i.invoice_id in selected)) continue
    const c = cents(selected[i.invoice_id])
    if (c <= 0) errors.push({ invoice: i.invoice_no, code: 'zero' })
    else if (c > cents(i.pending)) errors.push({ invoice: i.invoice_no, code: 'tooMuch' })
    apps.push({ invoice_id: i.invoice_id, amount: c / 100 })
  }
  const total = apps.reduce((s, a) => s + Math.round(a.amount * 100), 0) / 100
  return { apps, total, errors }
}

// El asiento que hará el ERP: pago → tercero al Debe y banco al Haber · cobro → al revés
export function previewEntry(paymentType, partnerAccount, cashAccount, total) {
  const partner = { account_no: partnerAccount, debit: 0, credit: 0 }
  const cash = { account_no: cashAccount, debit: 0, credit: 0 }
  if (paymentType === 'payment') { partner.debit = total; cash.credit = total; return [partner, cash] }
  cash.debit = total; partner.credit = total
  return [cash, partner]
}

// Asientos manuales que se pueden vincular como pago de un tercero: los que mueven su cuenta en el lado del pago
//   lines: filas de v_general_journal de la subcuenta del tercero · linked: claves "año/nº" ya vinculadas
export function linkCandidates(lines, paymentType, linked = new Set()) {
  return lines
    .filter((l) => l.source === 'manual' && Number(paymentType === 'payment' ? l.debit : l.credit) > 0)
    .map((l) => ({ entry_id: l.entry_id, year: l.fiscal_year, entry_no: l.entry_no, date: l.posting_date,
                   description: l.description, amount: Number(paymentType === 'payment' ? l.debit : l.credit),
                   linked: linked.has(`${l.fiscal_year}/${l.entry_no}`) }))
    .sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1 : b.entry_no - a.entry_no))
}
