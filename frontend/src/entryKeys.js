// ASIENTOS EN UNA LÍNEA (v0.41.1): qué hace cada tecla en el formulario de asiento. Va aparte, sin React, para
// probarlo tecla a tecla (tests/entryKeys.test.js). Como en ContaSol o A3: Enter avanza, el importe que falta para
// cuadrar se propone solo y una línea nueva aparece al terminar la última.

// Importe escrito («1210,5», «1.210,50» no: aquí se escribe sin miles) → céntimos (0.1 + 0.2 ≠ 0.3 en JavaScript)
export const cents = (v) => Math.round((parseFloat(String(v ?? '').replace(',', '.')) || 0) * 100)
const hasAmount = (l) => cents(l.debit) !== 0 || cents(l.credit) !== 0

// Lo que le falta al asiento para cuadrar, propuesto en la línea i si aún no tiene importe:
//   las demás suman más al Debe → se propone al Haber (y al revés) · null si ya cuadra o la línea tiene importe
export function suggestionFor(lines, i) {
  if (!lines[i] || hasAmount(lines[i])) return null
  const diff = lines.reduce((s, l, j) => (j === i ? s : s + cents(l.debit) - cents(l.credit)), 0)
  if (diff === 0) return null
  return { side: diff > 0 ? 'credit' : 'debit', cents: Math.abs(diff) }
}

// Enter en un campo. Devuelve la acción:
//   { type: 'focus', line, field }  ir a ese campo
//   { type: 'fill', side }          poner ahí el importe propuesto (y después pasar a la línea siguiente)
//   { type: 'next' }                pasar a la cuenta de la línea siguiente (o crearla si es la última)
//   { type: 'post' }                ir al botón «Contabilizar» (línea vacía y el asiento ya cuadra)
//   { type: 'stay' }                no moverse (cuenta sin encontrar, o línea vacía con el asiento sin cuadrar)
export function enterAction({ field, line, i, suggestion, balanced, resolved }) {
  if (field === 'account') {
    if (!String(line.accountText ?? '').trim() && !hasAmount(line)) return { type: balanced ? 'post' : 'stay' }
    if (!resolved) return { type: 'stay' }
    // Siempre al Debe (o al lado que pide la plantilla): si lo que falta va al Haber, Enter en el Debe vacío lleva allí
    return { type: 'focus', line: i, field: line.expect ?? 'debit' }
  }
  if (cents(line[field]) === 0 && suggestion?.side === field) return { type: 'fill', side: field }
  if (field === 'debit' && cents(line.debit) === 0) return { type: 'focus', line: i, field: 'credit' }
  return { type: 'next' }
}

// Otras teclas en una línea: «=» pone el importe propuesto · Ctrl + Supr borra la línea · «+» añade una debajo
export function lineKeyAction(e, field, suggestion) {
  if (e.key === 'Delete' && (e.ctrlKey || e.metaKey)) return { type: 'remove' }
  if (e.key === '+') return { type: 'add' }
  if (e.key === '=' && field !== 'account' && suggestion) return { type: 'fill', side: suggestion.side, stay: true }
  return null
}

// La línea que se borra: con más de dos se quita; con dos se vacía (un asiento tiene al menos dos líneas)
export const removeLineFrom = (lines, i, empty) => (lines.length > 2 ? lines.filter((_, j) => j !== i) : lines.map((l, j) => (j === i ? empty() : l)))
