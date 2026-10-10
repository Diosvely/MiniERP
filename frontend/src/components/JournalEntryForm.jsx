import { useEffect, useRef, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { accountName, money } from '../format'
import Link from './Link'
import { companyPath } from '../router'

const today = () => new Date().toISOString().slice(0, 10)
const emptyLine = () => ({ accountText: '', gl_account_id: '', debit: '', credit: '', description: '' })

// Atajo de ContaPlus / Sage / A3: el punto rellena con ceros hasta la longitud de la subcuenta.
//   572.1 → 57200001   ·   43.25 → 43000025
function expandDot(text, digits) {
  const t = text.trim()
  if (!t.includes('.')) return t
  const [left, right = ''] = t.split('.')
  const zeros = digits - left.length - right.length
  return zeros >= 0 ? left + '0'.repeat(zeros) + right : t
}

// Formulario de asiento: cabecera + líneas, con cuadre en vivo y manejo rápido con teclado
//   Enter: cuenta → Debe → Haber → "=" → cuenta de la línea siguiente
//   +    : nueva línea (en cualquier campo de la línea: un importe nunca lleva "+")
//   −    : borrar la línea, SOLO con el campo de cuenta vacío (en los importes el "−" se escribe normal)
//   Al borrar una línea con datos aparece "Línea borrada · Deshacer" durante 5 segundos
//   draft: asiento que propone el Tutor de asientos ({ id, description, lines: [{ account_no, debit, credit, description }] })
export default function JournalEntryForm({ company, onPosted, draft }) {
  const { t, language } = useI18n()
  const [accounts, setAccounts] = useState([])
  const [fiscalYears, setFiscalYears] = useState([])
  const [header, setHeader] = useState({ posting_date: today(), description: '', document_no: '' })
  const [lines, setLines] = useState([emptyLine(), emptyLine()])
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [saving, setSaving] = useState(false)
  const [postedOk, setPostedOk] = useState(false)   // tras contabilizar: enlace "Ver en el diario"
  const [focusTarget, setFocusTarget] = useState(null)   // { line, field } a enfocar tras re-dibujar
  const linesRef = useRef(null)
  const [removed, setRemoved] = useState(null)   // { line, index } · última línea borrada, para deshacer
  const undoTimer = useRef(null)

  // Solo subcuentas (posting): son las únicas donde se puede apuntar
  const loadAccounts = () => supabase.from('gl_accounts').select('id, account_no, name, name_en')
    .eq('company_id', company.id).eq('account_type', 'posting').order('account_no')
    .then(({ data }) => { setAccounts(data ?? []); return data ?? [] })

  useEffect(() => {
    loadAccounts()
    supabase.from('fiscal_years').select('id, year, starting_date, ending_date, status')
      .eq('company_id', company.id)
      .then(({ data }) => setFiscalYears(data ?? []))
  }, [company.id])

  // Asiento propuesto por el Tutor: se recargan las cuentas (puede haber subcuentas nuevas) y se rellenan las líneas.
  // Queda en pantalla para revisarlo: se guarda o contabiliza con los botones de siempre.
  useEffect(() => {
    if (!draft) return
    loadAccounts().then((list) => {
      const id = (no) => list.find((a) => a.account_no === no)?.id ?? ''
      setHeader((h) => ({ ...h, description: draft.description }))
      setLines(draft.lines.map((l) => ({
        accountText: l.account_no, gl_account_id: id(l.account_no),
        debit: Number(l.debit) ? String(l.debit) : '', credit: Number(l.credit) ? String(l.credit) : '',
        description: l.description ?? '',
      })))
      setError(''); setMessage(t('tutorLoaded'))
    })
  }, [draft?.id])

  // Mover el cursor cuando React ya ha dibujado la línea (por ejemplo, una línea nueva)
  useEffect(() => {
    if (!focusTarget) return
    const el = linesRef.current?.querySelector(
      `[data-line="${focusTarget.line}"][data-field="${focusTarget.field}"]`)
    el?.focus()
    el?.select?.()
    setFocusTarget(null)
  }, [focusTarget, lines])

  // Totales en céntimos para evitar errores de decimales (0.1 + 0.2 ≠ 0.3 en JavaScript)
  const cents = (v) => Math.round((parseFloat(String(v).replace(',', '.')) || 0) * 100)
  const totalDebit = lines.reduce((s, l) => s + cents(l.debit), 0)
  const totalCredit = lines.reduce((s, l) => s + cents(l.credit), 0)
  const difference = totalDebit - totalCredit
  const usedLines = lines.filter((l) => l.gl_account_id && (cents(l.debit) || cents(l.credit)))
  const balanced = difference === 0 && totalDebit > 0 && usedLines.length >= 2

  const byNo = (no) => accounts.find((a) => a.account_no === no)

  function updateLine(i, field, value) {
    setLines((prev) => {
      const copy = [...prev]
      copy[i] = { ...copy[i], [field]: value }
      // Un apunte va al Debe O al Haber: si escribes en uno, se vacía el otro
      if (field === 'debit' && value) copy[i].credit = ''
      if (field === 'credit' && value) copy[i].debit = ''
      // Al teclear la cuenta, se vincula en cuanto el número coincide exactamente
      if (field === 'accountText') copy[i].gl_account_id = byNo(value.trim())?.id ?? ''
      return copy
    })
  }

  // Al pulsar Enter en la cuenta: aplica el atajo del punto o elige la única coincidencia
  function resolveAccount(i) {
    const text = expandDot(lines[i].accountText, company.posting_account_digits)
    let found = byNo(text)
    if (!found && text) {
      const q = text.toLowerCase()
      const matches = accounts.filter((a) =>
        a.account_no.startsWith(q) || accountName(a, language).toLowerCase().includes(q))
      if (matches.length === 1) found = matches[0]
    }
    setLines((prev) => {
      const copy = [...prev]
      copy[i] = { ...copy[i], accountText: found ? found.account_no : text, gl_account_id: found?.id ?? '' }
      return copy
    })
    return Boolean(found)
  }

  function addLine(afterIndex) {
    setLines((prev) => {
      const copy = [...prev]
      copy.splice(afterIndex + 1, 0, emptyLine())
      return copy
    })
    setFocusTarget({ line: afterIndex + 1, field: 'account' })
  }

  function removeLine(i) {
    if (lines.length <= 2) return
    const gone = lines[i]
    setLines((prev) => prev.filter((_, j) => j !== i))
    setFocusTarget({ line: Math.max(0, i - 1), field: 'account' })
    // Solo se ofrece deshacer si la línea tenía algo escrito
    clearTimeout(undoTimer.current)
    if (gone.accountText || gone.debit || gone.credit) {
      setRemoved({ line: gone, index: i })
      undoTimer.current = setTimeout(() => setRemoved(null), 5000)
    } else {
      setRemoved(null)
    }
  }

  function undoRemove() {
    clearTimeout(undoTimer.current)
    const { line, index } = removed
    setLines((prev) => {
      const copy = [...prev]
      copy.splice(index, 0, line)
      return copy
    })
    setRemoved(null)
    setFocusTarget({ line: index, field: 'account' })
  }

  // Pone en la línea la diferencia que falta para cuadrar
  function fillDifference(i) {
    const others = (field) => lines.reduce((s, l, j) => (j === i ? s : s + cents(l[field])), 0)
    const diff = others('debit') - others('credit')
    setLines((prev) => {
      const copy = [...prev]
      copy[i] = { ...copy[i], debit: diff < 0 ? String(-diff / 100) : '', credit: diff > 0 ? String(diff / 100) : '' }
      return copy
    })
  }

  // Teclado dentro de una línea
  function onLineKey(e, i, field) {
    if (e.key === '+') {
      e.preventDefault()
      return addLine(i)
    }
    // "−" borra solo desde el campo de cuenta vacío: en Debe/Haber se escribe como signo
    if (e.key === '-' && field === 'account' && !lines[i].accountText.trim()) {
      e.preventDefault()
      return removeLine(i)
    }
    if (e.key !== 'Enter') return
    e.preventDefault()   // en el botón "=", Enter NO lo aplica: solo avanza
    if (field === 'account') {
      if (resolveAccount(i)) setFocusTarget({ line: i, field: 'debit' })
    } else if (field === 'debit') {
      setFocusTarget({ line: i, field: 'credit' })
    } else if (field === 'credit') {
      setFocusTarget({ line: i, field: 'eq' })
    } else if (field === 'eq') {
      setFocusTarget({ line: (i + 1) % lines.length, field: 'account' })
    }
  }

  async function save(post) {
    setError('')
    setMessage('')
    setPostedOk(false)
    const fy = fiscalYears.find((y) => header.posting_date >= y.starting_date && header.posting_date <= y.ending_date)
    if (!fy) return setError(t('noFiscalYear'))
    if (!header.description.trim()) return setError(t('needDescription'))
    if (usedLines.length < 2) return setError(t('needTwoLines'))
    if (post && !balanced) return setError(t('unbalanced'))

    setSaving(true)
    // 1) Cabecera del asiento (queda en borrador)
    const { data: entry, error: e1 } = await supabase.from('journal_entries')
      .insert({ ...header, document_no: header.document_no || null, company_id: company.id, fiscal_year_id: fy.id })
      .select('id').single()
    if (e1) { setSaving(false); return setError(e1.message) }

    // 2) Líneas (apuntes)
    const { error: e2 } = await supabase.from('journal_lines').insert(
      usedLines.map((l, i) => ({
        entry_id: entry.id,
        company_id: company.id,
        line_no: i + 1,
        gl_account_id: l.gl_account_id,
        debit: cents(l.debit) / 100,
        credit: cents(l.credit) / 100,
        description: l.description || null,
      })))
    if (e2) { setSaving(false); return setError(e2.message) }

    // 3) Contabilizar (la base de datos vuelve a validar el cuadre y el periodo)
    if (post) {
      const { data: entryNo, error: e3 } = await supabase.rpc('post_entry', { p_entry: entry.id })
      setSaving(false)
      if (e3) return setError(e3.message)
      setMessage(t('postedAs').replace('{n}', entryNo))
      setPostedOk(true)
    } else {
      setSaving(false)
      setMessage(t('savedDraft'))
    }
    setHeader({ posting_date: header.posting_date, description: '', document_no: '' })
    setLines([emptyLine(), emptyLine()])
    onPosted?.()
  }

  const listId = `cuentas-${company.id}`

  return (
    <section className="tarjeta formulario-asiento">
      <h2>{t('newEntry')}</h2>

      <div className="rejilla-cabecera">
        <label>{t('postingDate')}
          <input type="date" value={header.posting_date}
                 onChange={(e) => setHeader({ ...header, posting_date: e.target.value })} />
        </label>
        <label>{t('documentNo')}
          <input value={header.document_no} onChange={(e) => setHeader({ ...header, document_no: e.target.value })} />
        </label>
      </div>
      <input placeholder={t('entryDescription')} value={header.description}
             onChange={(e) => setHeader({ ...header, description: e.target.value })} />

      {accounts.length === 0 && (
        <p className="aviso">{t('noPostingAccounts')} <Link to={companyPath(company.id, 'accounts')} className="enlace">{t('actionOpenChart')} →</Link></p>
      )}
      <p className="ayuda">⌨ {t('keyboardHelp')}</p>

      {/* Sugerencias para el campo de cuenta: el número como valor y el nombre como etiqueta */}
      <datalist id={listId}>
        {accounts.map((a) => (
          <option key={a.id} value={a.account_no} label={accountName(a, language)} />
        ))}
      </datalist>

      <div ref={linesRef}>
        {lines.map((l, i) => {
          const account = accounts.find((a) => a.id === l.gl_account_id)
          const unknown = l.accountText.trim() !== '' && !account
          return (
            <div key={i} className="linea">
              <div className="cuenta-linea">
                <input
                  data-line={i} data-field="account" list={listId}
                  placeholder={t('selectAccount')} value={l.accountText} autoComplete="off"
                  className={unknown ? 'invalido' : ''}
                  onChange={(e) => updateLine(i, 'accountText', e.target.value)}
                  onKeyDown={(e) => onLineKey(e, i, 'account')}
                  onBlur={() => l.accountText && !l.gl_account_id && resolveAccount(i)} />
                <span className={unknown ? 'nombre-cuenta aviso' : 'nombre-cuenta'}>
                  {account ? accountName(account, language) : unknown ? t('accountNotFound') : ''}
                </span>
              </div>
              <input data-line={i} data-field="debit" placeholder={t('debit')} inputMode="decimal" value={l.debit}
                     onChange={(e) => updateLine(i, 'debit', e.target.value)}
                     onKeyDown={(e) => onLineKey(e, i, 'debit')} />
              <input data-line={i} data-field="credit" placeholder={t('credit')} inputMode="decimal" value={l.credit}
                     onChange={(e) => updateLine(i, 'credit', e.target.value)}
                     onKeyDown={(e) => onLineKey(e, i, 'credit')} />
              <div className="acciones-linea">
                <button type="button" className="secundario" data-line={i} data-field="eq"
                        onClick={() => fillDifference(i)} onKeyDown={(e) => onLineKey(e, i, 'eq')}
                        title={t('fillDifference')}>=</button>
                <button type="button" className="secundario" disabled={lines.length <= 2} tabIndex={-1}
                        onClick={() => removeLine(i)} title={t('removeLine')}>✕</button>
              </div>
            </div>
          )
        })}
      </div>

      {removed && (
        <p className="deshacer" role="status">
          {t('lineRemoved')}
          <button type="button" className="enlace" onClick={undoRemove}>↶ {t('undo')}</button>
        </p>
      )}

      <button type="button" className="secundario" onClick={() => addLine(lines.length - 1)}>
        + {t('addLine')}
      </button>

      <div className={`totales ${balanced ? 'ok' : 'descuadre'}`}>
        <span>{t('debit')}: <strong>{money(totalDebit / 100, language)}</strong></span>
        <span>{t('credit')}: <strong>{money(totalCredit / 100, language)}</strong></span>
        <span>{balanced ? `✓ ${t('balanced')}` : `${t('difference')}: ${money(difference / 100, language)}`}</span>
      </div>

      <div className="fila">
        <button type="button" className="secundario" disabled={saving} onClick={() => save(false)}>{t('saveDraft')}</button>
        <button type="button" disabled={saving || !balanced} onClick={() => save(true)}>{t('post')}</button>
      </div>

      {error && <p className="aviso">⚠ {error}</p>}
      {message && (
        <p className="exito">✓ {message}
          {postedOk && <> · <Link to={companyPath(company.id, 'journal')} className="enlace">{t('seeInJournal')} →</Link></>}
        </p>
      )}
    </section>
  )
}
