// Paso 217 · v0.41.1 · Asientos en una línea: Enter avanza y crea la línea nueva, el importe que falta se propone en gris, sin «=» ni «✕» (Ctrl + Supr o papelera)
// Cambia solo los trozos necesarios (con unas líneas de contexto) y crea los ficheros nuevos.
// Uso (desde la carpeta frontend):   node aplicar-paso217-web.mjs
// Se puede ejecutar dos veces sin problema. Si algo no encaja, lo dice y no toca ese trozo.
import fs from 'node:fs'

const NEW_FILES = {
  "src/entryKeys.js": "// ASIENTOS EN UNA LÍNEA (v0.41.1): qué hace cada tecla en el formulario de asiento. Va aparte, sin React, para\n// probarlo tecla a tecla (tests/entryKeys.test.js). Como en ContaSol o A3: Enter avanza, el importe que falta para\n// cuadrar se propone solo y una línea nueva aparece al terminar la última.\n\n// Importe escrito («1210,5», «1.210,50» no: aquí se escribe sin miles) → céntimos (0.1 + 0.2 ≠ 0.3 en JavaScript)\nexport const cents = (v) => Math.round((parseFloat(String(v ?? '').replace(',', '.')) || 0) * 100)\nconst hasAmount = (l) => cents(l.debit) !== 0 || cents(l.credit) !== 0\n\n// Lo que le falta al asiento para cuadrar, propuesto en la línea i si aún no tiene importe:\n//   las demás suman más al Debe → se propone al Haber (y al revés) · null si ya cuadra o la línea tiene importe\nexport function suggestionFor(lines, i) {\n  if (!lines[i] || hasAmount(lines[i])) return null\n  const diff = lines.reduce((s, l, j) => (j === i ? s : s + cents(l.debit) - cents(l.credit)), 0)\n  if (diff === 0) return null\n  return { side: diff > 0 ? 'credit' : 'debit', cents: Math.abs(diff) }\n}\n\n// Enter en un campo. Devuelve la acción:\n//   { type: 'focus', line, field }  ir a ese campo\n//   { type: 'fill', side }          poner ahí el importe propuesto (y después pasar a la línea siguiente)\n//   { type: 'next' }                pasar a la cuenta de la línea siguiente (o crearla si es la última)\n//   { type: 'post' }                ir al botón «Contabilizar» (línea vacía y el asiento ya cuadra)\n//   { type: 'stay' }                no moverse (cuenta sin encontrar, o línea vacía con el asiento sin cuadrar)\nexport function enterAction({ field, line, i, suggestion, balanced, resolved }) {\n  if (field === 'account') {\n    if (!String(line.accountText ?? '').trim() && !hasAmount(line)) return { type: balanced ? 'post' : 'stay' }\n    if (!resolved) return { type: 'stay' }\n    // Siempre al Debe (o al lado que pide la plantilla): si lo que falta va al Haber, Enter en el Debe vacío lleva allí\n    return { type: 'focus', line: i, field: line.expect ?? 'debit' }\n  }\n  if (cents(line[field]) === 0 && suggestion?.side === field) return { type: 'fill', side: field }\n  if (field === 'debit' && cents(line.debit) === 0) return { type: 'focus', line: i, field: 'credit' }\n  return { type: 'next' }\n}\n\n// Otras teclas en una línea: «=» pone el importe propuesto · Ctrl + Supr borra la línea · «+» añade una debajo\nexport function lineKeyAction(e, field, suggestion) {\n  if (e.key === 'Delete' && (e.ctrlKey || e.metaKey)) return { type: 'remove' }\n  if (e.key === '+') return { type: 'add' }\n  if (e.key === '=' && field !== 'account' && suggestion) return { type: 'fill', side: suggestion.side, stay: true }\n  return null\n}\n\n// La línea que se borra: con más de dos se quita; con dos se vacía (un asiento tiene al menos dos líneas)\nexport const removeLineFrom = (lines, i, empty) => (lines.length > 2 ? lines.filter((_, j) => j !== i) : lines.map((l, j) => (j === i ? empty() : l)))\n",
  "tests/entryKeys.test.js": "import { describe, expect, it } from 'vitest'\nimport { cents, enterAction, lineKeyAction, removeLineFrom, suggestionFor } from '../src/entryKeys'\n\nconst L = (accountText, debit = '', credit = '', extra = {}) => ({ accountText, debit, credit, ...extra })\n\ndescribe('asiento en una línea · importe propuesto (v0.41.1)', () => {\n  it('propone en la línea vacía lo que falta, en el lado contrario', () => {\n    const lines = [L('60000001', '1000'), L('47200021', '210'), L('')]\n    expect(suggestionFor(lines, 2)).toEqual({ side: 'credit', cents: 121000 })\n    expect(suggestionFor([L('57200001', '', '50,5'), L('')], 1)).toEqual({ side: 'debit', cents: 5050 })\n  })\n  it('no propone nada si ya cuadra o si la línea ya tiene importe', () => {\n    expect(suggestionFor([L('600', '100'), L('400', '', '100'), L('')], 2)).toBe(null)\n    expect(suggestionFor([L('600', '100'), L('400', '', '40')], 1)).toBe(null)\n  })\n  it('cuenta en céntimos: 0,1 + 0,2 = 0,3', () => {\n    expect(suggestionFor([L('a', '0,1'), L('b', '0.2'), L('')], 2)).toEqual({ side: 'credit', cents: 30 })\n    expect(cents('1210,50')).toBe(121050)\n  })\n})\n\ndescribe('asiento en una línea · Enter', () => {\n  const base = { i: 0, balanced: false, resolved: true, suggestion: null }\n  it('en la cuenta: al Debe (aunque lo que falta vaya al Haber: la 472 de una compra también va al Debe); o al lado que pide la plantilla', () => {\n    expect(enterAction({ ...base, field: 'account', line: L('600') })).toEqual({ type: 'focus', line: 0, field: 'debit' })\n    expect(enterAction({ ...base, field: 'account', line: L('472'), suggestion: { side: 'credit', cents: 100 } })).toEqual({ type: 'focus', line: 0, field: 'debit' })\n    expect(enterAction({ ...base, field: 'account', line: L('472', '', '', { expect: 'debit' }), suggestion: { side: 'credit', cents: 1 } })).toEqual({ type: 'focus', line: 0, field: 'debit' })\n  })\n  it('en la cuenta sin encontrar: se queda', () => {\n    expect(enterAction({ ...base, field: 'account', line: L('999'), resolved: false })).toEqual({ type: 'stay' })\n  })\n  it('en una línea vacía: si el asiento cuadra, a «Contabilizar»; si no, se queda', () => {\n    expect(enterAction({ ...base, field: 'account', line: L(''), balanced: true })).toEqual({ type: 'post' })\n    expect(enterAction({ ...base, field: 'account', line: L('') })).toEqual({ type: 'stay' })\n  })\n  it('en el Debe: con importe, a la línea siguiente; vacío, al Haber', () => {\n    expect(enterAction({ ...base, field: 'debit', line: L('600', '100') })).toEqual({ type: 'next' })\n    expect(enterAction({ ...base, field: 'debit', line: L('400') })).toEqual({ type: 'focus', line: 0, field: 'credit' })\n  })\n  it('en el campo del importe propuesto, vacío: lo pone (y después sigue)', () => {\n    expect(enterAction({ ...base, field: 'credit', line: L('400'), suggestion: { side: 'credit', cents: 121000 } })).toEqual({ type: 'fill', side: 'credit' })\n    expect(enterAction({ ...base, field: 'debit', line: L('572'), suggestion: { side: 'debit', cents: 5 } })).toEqual({ type: 'fill', side: 'debit' })\n  })\n  it('en el Haber: siempre a la línea siguiente (o una nueva)', () => {\n    expect(enterAction({ ...base, field: 'credit', line: L('400', '', '50') })).toEqual({ type: 'next' })\n    expect(enterAction({ ...base, field: 'credit', line: L('400') })).toEqual({ type: 'next' })\n  })\n})\n\ndescribe('asiento en una línea · otras teclas', () => {\n  const k = (key, mods = {}) => ({ key, ctrlKey: false, metaKey: false, ...mods })\n  it('Ctrl + Supr borra la línea (también ⌘ + Supr en el Mac); Supr sola no', () => {\n    expect(lineKeyAction(k('Delete', { ctrlKey: true }), 'debit', null)).toEqual({ type: 'remove' })\n    expect(lineKeyAction(k('Delete', { metaKey: true }), 'account', null)).toEqual({ type: 'remove' })\n    expect(lineKeyAction(k('Delete'), 'account', null)).toBe(null)\n  })\n  it('«=» pone el importe propuesto en su lado, solo en los importes y si hay propuesta', () => {\n    expect(lineKeyAction(k('='), 'debit', { side: 'credit', cents: 5 })).toEqual({ type: 'fill', side: 'credit', stay: true })\n    expect(lineKeyAction(k('='), 'account', { side: 'credit', cents: 5 })).toBe(null)\n    expect(lineKeyAction(k('='), 'credit', null)).toBe(null)\n  })\n  it('«+» añade una línea debajo', () => {\n    expect(lineKeyAction(k('+'), 'account', null)).toEqual({ type: 'add' })\n  })\n  it('borrar: con más de dos líneas se quita; con dos, se vacía', () => {\n    const e = () => L('')\n    expect(removeLineFrom([L('a'), L('b'), L('c')], 1, e).map((l) => l.accountText)).toEqual(['a', 'c'])\n    expect(removeLineFrom([L('a'), L('b')], 0, e).map((l) => l.accountText)).toEqual(['', 'b'])\n  })\n})\n"
}
const EDITS = [
  [
    "src/components/JournalEntryForm.jsx",
    "import { controlledLines, moduleScreen } from '../controlled'\n\n",
    "import { controlledLines, moduleScreen } from '../controlled'\nimport { cents, enterAction, lineKeyAction, removeLineFrom, suggestionFor } from '../entryKeys'\nimport { Trash2 } from 'lucide-react'\n\n"
  ],
  [
    "src/components/JournalEntryForm.jsx",
    "\n// Formulario de asiento: cabecera + líneas, con cuadre en vivo y manejo rápido con teclado\n//   Enter: cuenta → Debe → Haber → \"=\" → cuenta de la línea siguiente\n//   +    : nueva línea (en cualquier campo de la línea: un importe nunca lleva \"+\")\n//   −    : borrar la línea, SOLO con el campo de cuenta vacío (en los importes el \"−\" se escribe normal)\n",
    "\n// Formulario de asiento: cabecera + líneas, con cuadre en vivo y manejo rápido con teclado (v0.41.1: una fila por línea,\n// la lógica de cada tecla está en src/entryKeys.js)\n//   Enter: cuenta → Debe (o el lado del importe propuesto) → línea siguiente; al final de la última, una línea nueva\n//   El importe que falta para cuadrar se propone en gris en la línea vacía: Enter o «=» lo ponen\n//   Enter en una línea vacía con el asiento cuadrado → botón «Contabilizar»\n//   Ctrl + Supr (o la papelera al pasar el ratón): borrar la línea · +: nueva línea debajo\n//   −    : borrar la línea, SOLO con el campo de cuenta vacío (en los importes el \"−\" se escribe normal)\n"
  ],
  [
    "src/components/JournalEntryForm.jsx",
    "  const linesRef = useRef(null)\n  const [removed, setRemoved] = useState(null)   // { line, index } · última línea borrada, para deshacer\n",
    "  const linesRef = useRef(null)\n  const postRef = useRef(null)   // botón «Contabilizar»: Enter en una línea vacía con el asiento cuadrado\n  const [removed, setRemoved] = useState(null)   // { line, index } · última línea borrada, para deshacer\n"
  ],
  [
    "src/components/JournalEntryForm.jsx",
    "    if (!focusTarget) return\n    const el = linesRef.current?.querySelector(\n      `[data-line=\"${focusTarget.line}\"][data-field=\"${focusTarget.field}\"]`)\n",
    "    if (!focusTarget) return\n    const el = focusTarget.field === 'post' ? postRef.current : linesRef.current?.querySelector(\n      `[data-line=\"${focusTarget.line}\"][data-field=\"${focusTarget.field}\"]`)\n"
  ],
  [
    "src/components/JournalEntryForm.jsx",
    "\n  // Totales en céntimos para evitar errores de decimales (0.1 + 0.2 ≠ 0.3 en JavaScript)\n  const cents = (v) => Math.round((parseFloat(String(v).replace(',', '.')) || 0) * 100)\n  const totalDebit = lines.reduce((s, l) => s + cents(l.debit), 0)\n",
    "\n  // Totales en céntimos para evitar errores de decimales (0.1 + 0.2 ≠ 0.3 en JavaScript): cents() de entryKeys.js\n  const totalDebit = lines.reduce((s, l) => s + cents(l.debit), 0)\n"
  ],
  [
    "src/components/JournalEntryForm.jsx",
    "    setSuggest(null)\n    setFocusTarget({ line: i, field: lines[i].expect ?? 'debit' })\n  }\n",
    "    setSuggest(null)\n    setFocusTarget({ line: i, field: lines[i].expect ?? 'debit' })   // al lado que pide la plantilla; si no, al Debe\n  }\n"
  ],
  [
    "src/components/JournalEntryForm.jsx",
    "  function removeLine(i) {\n    if (lines.length <= 2) return\n    const gone = lines[i]\n",
    "  function removeLine(i) {\n    const gone = lines[i]\n"
  ],
  [
    "src/components/JournalEntryForm.jsx",
    "    const gone = lines[i]\n    setLines((prev) => prev.filter((_, j) => j !== i))\n    setFocusTarget({ line: Math.max(0, i - 1), field: 'account' })\n",
    "    const gone = lines[i]\n    setLines((prev) => removeLineFrom(prev, i, emptyLine))\n    setFocusTarget({ line: Math.max(0, i - 1), field: 'account' })\n"
  ],
  [
    "src/components/JournalEntryForm.jsx",
    "      const copy = [...prev]\n      copy.splice(index, 0, line)\n      return copy\n",
    "      const copy = [...prev]\n      if (prev.length === 2 && !prev[index].accountText && !prev[index].debit && !prev[index].credit) copy[index] = line   // se había vaciado\n      else copy.splice(index, 0, line)\n      return copy\n"
  ],
  [
    "src/components/JournalEntryForm.jsx",
    "\n  // Pone en la línea la diferencia que falta para cuadrar\n  function fillDifference(i) {\n    const others = (field) => lines.reduce((s, l, j) => (j === i ? s : s + cents(l[field])), 0)\n    const diff = others('debit') - others('credit')\n    setLines((prev) => {\n",
    "\n  // Pone en la línea el importe propuesto (lo que falta para cuadrar), en su lado\n  function fillSuggestion(i, sug) {\n    const amount = String(sug.cents / 100).replace('.', ',')\n    setLines((prev) => {\n"
  ],
  [
    "src/components/JournalEntryForm.jsx",
    "      const copy = [...prev]\n      copy[i] = { ...copy[i], debit: diff < 0 ? String(-diff / 100) : '', credit: diff > 0 ? String(diff / 100) : '' }\n      return copy\n",
    "      const copy = [...prev]\n      copy[i] = { ...copy[i], debit: sug.side === 'debit' ? amount : '', credit: sug.side === 'credit' ? amount : '' }\n      return copy\n"
  ],
  [
    "src/components/JournalEntryForm.jsx",
    "\n  // Teclado dentro de una línea\n",
    "\n  // A la cuenta de la línea siguiente; después de la última, una línea nueva\n  const nextLine = (i) => (i === lines.length - 1 ? addLine(i) : setFocusTarget({ line: i + 1, field: 'account' }))\n\n  // Teclado dentro de una línea\n"
  ],
  [
    "src/components/JournalEntryForm.jsx",
    "  function onLineKey(e, i, field) {\n    if (e.key === '+') {\n      e.preventDefault()\n",
    "  function onLineKey(e, i, field) {\n    const sug = suggestionFor(lines, i)\n    const other = lineKeyAction(e, field, sug)\n    if (other) {\n      e.preventDefault()\n"
  ],
  [
    "src/components/JournalEntryForm.jsx",
    "      e.preventDefault()\n      return addLine(i)\n    }\n",
    "      e.preventDefault()\n      if (other.type === 'remove') return removeLine(i)\n      if (other.type === 'add') return addLine(i)\n      if (other.type === 'fill') return fillSuggestion(i, sug)\n    }\n"
  ],
  [
    "src/components/JournalEntryForm.jsx",
    "    if (e.key !== 'Enter') return\n    e.preventDefault()   // en el botón \"=\", Enter NO lo aplica: solo avanza\n    if (field === 'account') {\n      if (resolveAccount(i)) setFocusTarget({ line: i, field: 'debit' })\n    } else if (field === 'debit') {\n      setFocusTarget({ line: i, field: 'credit' })\n    } else if (field === 'credit') {\n      setFocusTarget({ line: i, field: 'eq' })\n    } else if (field === 'eq') {\n      setFocusTarget({ line: (i + 1) % lines.length, field: 'account' })\n    }\n  }\n",
    "    if (e.key !== 'Enter') return\n    e.preventDefault()\n    const resolved = field === 'account' && lines[i].accountText.trim() ? resolveAccount(i) : Boolean(lines[i].gl_account_id)\n    const act = enterAction({ field, line: lines[i], i, suggestion: sug, balanced, resolved })\n    if (act.type === 'focus') setFocusTarget({ line: act.line, field: act.field })\n    else if (act.type === 'post') setFocusTarget({ field: 'post' })\n    else if (act.type === 'fill') { fillSuggestion(i, sug); nextLine(i) }\n    else if (act.type === 'next') nextLine(i)\n  }\n"
  ],
  [
    "src/components/JournalEntryForm.jsx",
    "\n      <div className=\"rejilla-cabecera\">\n        <label>{t('postingDate')}\n",
    "\n      <div className=\"rejilla-cabecera cabecera-asiento\">\n        <label>{t('postingDate')}\n"
  ],
  [
    "src/components/JournalEntryForm.jsx",
    "        </label>\n      </div>\n",
    "        </label>\n        <label className=\"concepto-asiento\">{t('entryConcept')}\n          <input placeholder={t('entryDescription')} value={header.description}\n                 onChange={(e) => setHeader({ ...header, description: e.target.value })} />\n        </label>\n      </div>\n"
  ],
  [
    "src/components/JournalEntryForm.jsx",
    "        </label>\n      </div>\n      <input placeholder={t('entryDescription')} value={header.description}\n             onChange={(e) => setHeader({ ...header, description: e.target.value })} />\n\n      {/* ¿Qué ha pasado? Plantillas de los asientos más frecuentes */}\n",
    "        </label>\n      </div>\n\n      {/* ¿Qué ha pasado? Plantillas de los asientos más frecuentes */}\n"
  ],
  [
    "src/components/JournalEntryForm.jsx",
    "\n      <div ref={linesRef}>\n        {lines.map((l, i) => {\n",
    "\n      <div ref={linesRef} className=\"lineas-asiento\">\n        <div className=\"linea cabecera-lineas\" aria-hidden=\"true\">\n          <span>{t('account')}</span><span>{t('debit')}</span><span>{t('credit')}</span><span />\n        </div>\n        {lines.map((l, i) => {\n"
  ],
  [
    "src/components/JournalEntryForm.jsx",
    "          const listId = `cuentas-${i}`\n          return (\n",
    "          const listId = `cuentas-${i}`\n          const sug = suggestionFor(lines, i)\n          // Importe propuesto (lo que falta para cuadrar), en gris en su lado: Enter o «=» lo ponen\n          const hint = (side) => (sug?.side === side ? `= ${money(sug.cents / 100, language)}` : t(side))\n          return (\n"
  ],
  [
    "src/components/JournalEntryForm.jsx",
    "              </div>\n              <input data-line={i} data-field=\"debit\" placeholder={t('debit')} inputMode=\"decimal\" value={l.debit}\n                     aria-label={t('debit')} className={l.expect === 'debit' ? 'esperado' : ''}\n                     onChange={(e) => updateLine(i, 'debit', e.target.value)}\n",
    "              </div>\n              <input data-line={i} data-field=\"debit\" placeholder={hint('debit')} inputMode=\"decimal\" value={l.debit}\n                     aria-label={t('debit')} title={sug?.side === 'debit' ? t('suggestedAmount') : undefined}\n                     className={[l.expect === 'debit' ? 'esperado' : '', sug?.side === 'debit' ? 'propuesto' : ''].join(' ').trim()}\n                     onChange={(e) => updateLine(i, 'debit', e.target.value)}\n"
  ],
  [
    "src/components/JournalEntryForm.jsx",
    "                     onKeyDown={(e) => onLineKey(e, i, 'debit')} />\n              <input data-line={i} data-field=\"credit\" placeholder={t('credit')} inputMode=\"decimal\" value={l.credit}\n                     aria-label={t('credit')} className={l.expect === 'credit' ? 'esperado' : ''}\n                     onChange={(e) => updateLine(i, 'credit', e.target.value)}\n",
    "                     onKeyDown={(e) => onLineKey(e, i, 'debit')} />\n              <input data-line={i} data-field=\"credit\" placeholder={hint('credit')} inputMode=\"decimal\" value={l.credit}\n                     aria-label={t('credit')} title={sug?.side === 'credit' ? t('suggestedAmount') : undefined}\n                     className={[l.expect === 'credit' ? 'esperado' : '', sug?.side === 'credit' ? 'propuesto' : ''].join(' ').trim()}\n                     onChange={(e) => updateLine(i, 'credit', e.target.value)}\n"
  ],
  [
    "src/components/JournalEntryForm.jsx",
    "                     onKeyDown={(e) => onLineKey(e, i, 'credit')} />\n              <div className=\"acciones-linea\">\n                <button type=\"button\" className=\"secundario\" data-line={i} data-field=\"eq\"\n                        onClick={() => fillDifference(i)} onKeyDown={(e) => onLineKey(e, i, 'eq')}\n                        title={t('fillDifference')}>=</button>\n                <button type=\"button\" className=\"secundario\" disabled={lines.length <= 2} tabIndex={-1}\n                        onClick={() => removeLine(i)} title={t('removeLine')}>✕</button>\n              </div>\n            </div>\n",
    "                     onKeyDown={(e) => onLineKey(e, i, 'credit')} />\n              <button type=\"button\" className=\"papelera\" tabIndex={-1} onClick={() => removeLine(i)}\n                      title={t('removeLineKey')} aria-label={`${t('removeLine')} ${i + 1}`}>\n                <Trash2 size={16} aria-hidden=\"true\" />\n              </button>\n            </div>\n"
  ],
  [
    "src/components/JournalEntryForm.jsx",
    "        <button type=\"button\" className=\"secundario\" disabled={saving} onClick={() => save(false)}>{t('saveDraft')}</button>\n        <button type=\"button\" disabled={saving || !balanced || blocked} title={blocked ? t('ctl.postDisabled') : undefined}\n                onClick={() => save(true)}>{t('post')}</button>\n",
    "        <button type=\"button\" className=\"secundario\" disabled={saving} onClick={() => save(false)}>{t('saveDraft')}</button>\n        <button type=\"button\" ref={postRef} disabled={saving || !balanced || blocked} title={blocked ? t('ctl.postDisabled') : undefined}\n                onClick={() => save(true)}>{t('post')}</button>\n"
  ],
  [
    "src/i18n/en.js",
    "  credit: 'Credit',\n  keyboardHelp: 'Enter: account → Debit → Credit → = → next line · +: new line · − (empty account): delete line · 572.1 = 57200001',\n  accountNotFound: 'Posting account not found',\n",
    "  credit: 'Credit',\n  keyboardHelp: 'Enter: account → amount → next line (a new one at the end) · the amount needed to balance shows in grey: Enter or = fills it in · empty line + Enter when balanced: Post · Ctrl + Del: delete line · 572.1 = 57200001',\n  entryConcept: 'Description',\n  suggestedAmount: 'Amount needed to balance: press Enter or = to fill it in',\n  removeLineKey: 'Delete the line (Ctrl + Del)',\n  accountNotFound: 'Posting account not found',\n"
  ],
  [
    "src/i18n/en.js",
    "  },\n  tplNote: 'They fill in the accounts; you type the amounts and press \"=\" on the total line. They do not calculate {tax}: for an invoice with the tax calculated, use',\n  tplLoaded: 'Template loaded: type the amounts in the highlighted fields and press \"=\" on the total line.',\n",
    "  },\n  tplNote: 'They fill in the accounts; you type the amounts and, on the total line, Enter or \"=\" fill in the rest. They do not calculate {tax}: for an invoice with the tax calculated, use',\n  tplLoaded: 'Template loaded: type the amounts in the highlighted fields and press \"=\" on the total line.',\n"
  ],
  [
    "src/i18n/es.js",
    "  credit: 'Haber',\n  keyboardHelp: 'Enter: cuenta → Debe → Haber → = → línea siguiente · +: nueva línea · − (con la cuenta vacía): borrar línea · 572.1 = 57200001',\n  accountNotFound: 'No existe esa subcuenta',\n",
    "  credit: 'Haber',\n  keyboardHelp: 'Enter: cuenta → importe → línea siguiente (al final, una nueva) · lo que falta para cuadrar sale en gris: Enter o = lo ponen · línea vacía + Enter con el asiento cuadrado: Contabilizar · Ctrl + Supr: borrar línea · 572.1 = 57200001',\n  entryConcept: 'Concepto',\n  suggestedAmount: 'Lo que falta para cuadrar: pulsa Enter o = para ponerlo',\n  removeLineKey: 'Borrar la línea (Ctrl + Supr)',\n  accountNotFound: 'No existe esa subcuenta',\n"
  ],
  [
    "src/i18n/es.js",
    "  },\n  tplNote: 'Rellenan las cuentas; tú escribes los importes y pulsas \"=\" en la línea del total. No calculan el {tax}: para una factura con el impuesto calculado, usa',\n  tplLoaded: 'Plantilla cargada: escribe los importes en los campos marcados y pulsa \"=\" en la línea del total.',\n",
    "  },\n  tplNote: 'Rellenan las cuentas; tú escribes los importes y, en la línea del total, Enter o \"=\" ponen lo que falta. No calculan el {tax}: para una factura con el impuesto calculado, usa',\n  tplLoaded: 'Plantilla cargada: escribe los importes en los campos marcados y pulsa \"=\" en la línea del total.',\n"
  ],
  [
    "src/index.css",
    "input.esperado { border-color: var(--primario); box-shadow: inset 0 0 0 1px var(--primario); }\n.linea-total .acciones-linea button:first-child { border-width: 2px; font-weight: 700; }\n\n",
    "input.esperado { border-color: var(--primario); box-shadow: inset 0 0 0 1px var(--primario); }\n/* v0.41.1 · asiento en una línea: el importe propuesto en gris (placeholder) y la papelera */\ninput.propuesto::placeholder { color: var(--primario); opacity: .75; font-style: italic; }\n.linea input[inputmode=\"decimal\"] { text-align: right; font-variant-numeric: tabular-nums; }\n.papelera { background: transparent; color: var(--suave); border: 0; padding: 6px; align-self: center; line-height: 0; }\n.papelera:hover, .papelera:focus-visible { color: var(--aviso); background: color-mix(in srgb, var(--aviso) 10%, transparent); }\n.cabecera-lineas { display: none; }\n.cabecera-asiento { grid-template-columns: repeat(2, minmax(0, 1fr)); }\n.cabecera-asiento .concepto-asiento { grid-column: 1 / -1; }\n@media (min-width: 700px) {\n  /* PC: una fila por línea · Cuenta (con su nombre al lado) | Debe | Haber | papelera */\n  .lineas-asiento .linea { grid-template-columns: minmax(0, 1fr) 9.5em 9.5em 2.2em; align-items: center; padding: 3px 0; }\n  .lineas-asiento .cuenta-linea { grid-column: auto; flex-direction: row; align-items: center; gap: 8px; }\n  .lineas-asiento .cuenta-linea input { width: 13em; flex: none; }\n  .lineas-asiento .nombre-cuenta { flex: 1; min-width: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; padding: 0; }\n  .lineas-asiento .cabecera-lineas { display: grid; padding: 0 0 2px; border-bottom: 1px solid var(--borde); color: var(--suave); font-size: .8rem; }\n  .lineas-asiento .cabecera-lineas span:nth-child(2), .lineas-asiento .cabecera-lineas span:nth-child(3) { text-align: right; padding-right: 10px; }\n  .papelera { opacity: 0; }\n  .linea:hover .papelera, .linea:focus-within .papelera, .papelera:focus-visible { opacity: 1; }\n  .cabecera-asiento { grid-template-columns: 11em 10em minmax(0, 1fr); }\n  .cabecera-asiento .concepto-asiento { grid-column: auto; }\n}\n\n"
  ]
]

let warnings = 0
const read = (f) => fs.readFileSync(f, 'utf8')
// Trabaja con saltos de línea \n y respeta los \r\n del fichero si los tiene (Windows)
const edit = (f, fn) => {
  const raw = read(f)
  const crlf = raw.includes('\r\n')
  const before = raw.replace(/\r\n/g, '\n')
  const after = fn(before)
  if (after !== before) fs.writeFileSync(f, crlf ? after.replace(/\n/g, '\r\n') : after)
}

for (const [f, content] of Object.entries(NEW_FILES)) {
  if (fs.existsSync(f) && read(f).replace(/\r\n/g, '\n') === content) console.log(`· ${f} ya estaba`)
  else { fs.writeFileSync(f, content); console.log(`✓ ${f} creado`) }
}

for (const [f, from, to] of EDITS) {
  edit(f, (s) => {
    if (s.includes(to)) { console.log(`· ${f}: ya estaba cambiado`); return s }
    if (!s.includes(from)) { warnings++; console.log(`⚠ ${f}: no encuentro el trozo que empieza por:\n    ${from.split('\n')[0].trim()}`); return s }
    console.log(`✓ ${f}: ${from.split('\n')[0].trim().slice(0, 70)}…`)
    return s.replace(from, to)
  })
}


console.log(warnings ? `\n⚠ ${warnings} aviso(s): pásame el mensaje y lo vemos.` : '\n✔ Paso 217 aplicado. Ahora: npm run lint · npm test · npm run build')
