// SALDOS AL REVÉS EN EL BALANCE (v0.57.0 · ADR 0057): el ERP no compensa una cuenta con saldo contrario a su naturaleza
// (un proveedor deudor, una caja acreedora…): la presenta en la otra masa del balance y avisa. La base de datos dice en
// qué partida cae cada una (erp.fs_line_anomalies); aquí se cuenta cuántas hay en cada partida y en las que la contienen.
//   rows: las partidas del Balance ({ code, parent }) · anomalies: [{ line_code, account_no, severity, … }]
//   → { <partida>: { n, errors } }, también en las partidas superiores (Existencias → Activo corriente → Total activo)
export function anomalyCounts(rows, anomalies) {
  const parent = new Map((rows ?? []).map((r) => [r.code, r.parent]))
  const out = {}
  for (const a of anomalies ?? []) {
    const seen = new Set()
    for (let code = a.line_code; code && !seen.has(code); code = parent.get(code)) {
      seen.add(code)
      const c = (out[code] ??= { n: 0, errors: 0 })
      c.n += 1
      if (a.severity === 'error') c.errors += 1
    }
  }
  return out
}

// Las cuentas con saldo al revés, por número de cuenta (para marcarlas al desplegar una partida)
export const anomalyByAccount = (anomalies) => new Map((anomalies ?? []).map((a) => [a.account_no, a]))

// v0.59.2 · Al desplegar una partida que tiene sublíneas (II. Deudas a corto plazo), sus cuentas salen todas juntas:
// a cada una se le dice en qué sublínea se presenta (1. Deudas con entidades de crédito). null si es la misma partida.
export function accountSubLine(account, lineCode, rows) {
  if (!account?.line_code || account.line_code === lineCode) return null
  return rows.find((r) => r.code === account.line_code) ?? null
}
