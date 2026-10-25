// CUENTAS CONTROLADAS (v0.33.0): la misma regla que la base de datos (erp.control_rules, erp.controlled_lines, 0036)
// para avisar ANTES de contabilizar. Quien decide sigue siendo la base de datos: en modo estricto no deja contabilizar.
//   rules: filas de control_rules [{ account_prefix, modules, side }] · gana el prefijo más largo (4009 libre dentro de 400)

export function ruleFor(accountNo, rules) {
  let best = null
  for (const r of rules) {
    if (String(accountNo ?? '').startsWith(r.account_prefix) && (!best || r.account_prefix.length > best.account_prefix.length)) best = r
  }
  return best
}

// Líneas que tocan una cuenta controlada por su lado controlado
//   lines: [{ account_no, debit, credit }]  →  [{ line, account_no, modules, side }]
export function controlledLines(lines, rules) {
  const out = []
  lines.forEach((l, i) => {
    const r = ruleFor(l.account_no, rules)
    if (!r || !r.modules?.length) return
    const debit = Number(l.debit) || 0
    const credit = Number(l.credit) || 0
    if (r.side === 'both' || (r.side === 'debit' && debit > 0) || (r.side === 'credit' && credit > 0)) {
      out.push({ line: i + 1, account_no: l.account_no, modules: r.modules, side: r.side })
    }
  })
  return out
}

// Pantalla donde se registra lo que mueve esa cuenta: un pago, en Cobros y pagos; el IVA, en Facturas…
export function moduleScreen(modules) {
  const m = Array.isArray(modules) ? modules : String(modules ?? '').split(/,\s*/)
  if (m.includes('payments')) return 'payments'
  if (m.includes('financing')) return 'financing'   // v0.43.0 (antes que las facturas: la 524 también la mueve la factura de la cuota)
  if (m.includes('invoices')) return 'invoices'
  if (m.includes('settlement')) return 'settlement'
  if (m.includes('assets')) return 'assets'
  if (m.includes('payroll')) return 'payroll'   // v0.38.0
  if (m.includes('corporate_tax')) return 'corporate_tax'   // v0.41.0
  if (m.includes('equity')) return 'equity'   // v0.42.0
  if (m.includes('grants')) return 'grants'   // v0.44.0
  if (m.includes('accruals') || m.includes('impairments') || m.includes('provisions') || m.includes('inventory')) return 'adjustments'   // v0.36.0 / v0.37.0
  return 'journal'
}

// Resumen de una comprobación del auditor para la cabecera: cuántas en verde, avisos, errores e informativas
export function checksSummary(rows) {
  const s = { ok: 0, info: 0, warning: 0, error: 0 }
  for (const r of rows) s[r.status] = (s[r.status] ?? 0) + 1
  return s
}
