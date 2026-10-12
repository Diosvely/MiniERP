// ANÁLISIS HORIZONTAL: comparar una cifra con la del ejercicio anterior (Balance y PyG)

// Fecha de corte del ejercicio anterior (la misma regla que erp.financial_statement, migración 0032):
//   · Balance → su cierre (null = ejercicio completo): es la foto aprobada con la que se compara
//   · PyG     → la misma fecha un año antes (mismo periodo); un 29 de febrero pasa a 28
export function prevCutoff(statement, toDate) {
  if (statement === 'balance' || !toDate) return null
  const md = toDate.slice(4) === '-02-29' ? '-02-28' : toDate.slice(4)
  return `${Number(toDate.slice(0, 4)) - 1}${md}`
}

// Variación en % sobre el valor absoluto del anterior: "+12,5 %" · "−8 %" · "—" si el anterior es 0
export function changePct(amount, prev, language = 'es') {
  const base = Math.abs(Number(prev))
  if (base < 0.005) return '—'
  const v = ((Number(amount) - Number(prev)) / base) * 100
  const n = Math.abs(v).toLocaleString(language === 'en' ? 'en-GB' : 'es-ES', { maximumFractionDigits: 1 })
  return `${v > 0.05 ? '+' : v < -0.05 ? '−' : ''}${n} %`
}
