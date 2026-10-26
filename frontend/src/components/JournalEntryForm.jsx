import { useEffect, useRef, useState } from 'react'
import { supabase } from '../supabase'
import { fetchAll } from '../paging'
import { useI18n } from '../i18n'
import { workDate } from '../workDate'
import DateField from './DateField'
import { accountName, money } from '../format'
import Link from './Link'
import { companyPath, navigate } from '../router'
import ErrorBox from './ErrorBox'
import { TEMPLATES } from '../templates'
import Term from './Term'
import { ICON } from '../icons'
import { controlledLines, moduleScreen } from '../controlled'
import { cents, enterAction, lineKeyAction, removeLineFrom, suggestionFor } from '../entryKeys'
import { Trash2 } from 'lucide-react'

const emptyLine = () => ({ accountText: '', gl_account_id: '', debit: '', credit: '', description: '' })

// Búsqueda sin acentos ni mayúsculas: "camion" encuentra "Camión"
const norm = (s) => String(s ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase()

// Atajo de ContaPlus / Sage / A3: el punto rellena con ceros hasta la longitud de la subcuenta.
//   572.1 → 57200001   ·   43.25 → 43000025
function expandDot(text, digits) {
  const t = text.trim()
  if (!t.includes('.')) return t
  const [left, right = ''] = t.split('.')
  const zeros = digits - left.length - right.length
  return zeros >= 0 ? left + '0'.repeat(zeros) + right : t
}

// Formulario de asiento: cabecera + líneas, con cuadre en vivo y manejo rápido con teclado (v0.41.1: una fila por línea,
// la lógica de cada tecla está en src/entryKeys.js)
//   Enter: cuenta → Debe (o el lado del importe propuesto) → línea siguiente; al final de la última, una línea nueva
//   El importe que falta para cuadrar se propone en gris en la línea vacía: Enter o «=» lo ponen
//   Enter en una línea vacía con el asiento cuadrado → botón «Contabilizar»
//   Ctrl + Supr (o la papelera al pasar el ratón): borrar la línea · +: nueva línea debajo
//   −    : borrar la línea, SOLO con el campo de cuenta vacío (en los importes el "−" se escribe normal)
//   Al borrar una línea con datos aparece "Línea borrada · Deshacer" durante 5 segundos
//   Cuenta: se busca por número (572…) o por nombre ("caja", "bancos"); ↑ ↓ para elegir, Enter, Escape para cerrar
//   Plantillas "¿Qué ha pasado?": rellenan las cuentas; tú solo escribes los importes
//   draft: asiento que propone el Tutor de asientos ({ id, description, lines: [{ account_no, debit, credit, description }] })
//   editId: v0.47.0 · un borrador guardado que se sigue editando (se abre desde la pantalla «Asientos»)
export default function JournalEntryForm({ company, onPosted, draft, editId }) {
  const { t, language } = useI18n()
  const [accounts, setAccounts] = useState([])
  const [fiscalYears, setFiscalYears] = useState([])
  const [header, setHeader] = useState({ posting_date: workDate(company), description: '', document_no: '' })
  const [lines, setLines] = useState([emptyLine(), emptyLine()])
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [saving, setSaving] = useState(false)
  const [postedOk, setPostedOk] = useState(false)   // tras contabilizar: enlace "Ver en el diario"
  const [focusTarget, setFocusTarget] = useState(null)   // { line, field } a enfocar tras re-dibujar
  const linesRef = useRef(null)
  const postRef = useRef(null)   // botón «Contabilizar»: Enter en una línea vacía con el asiento cuadrado
  const [removed, setRemoved] = useState(null)   // { line, index } · última línea borrada, para deshacer
  const undoTimer = useRef(null)
  const [suggest, setSuggest] = useState(null)   // { line, active } · lista de cuentas abierta bajo una línea
  const [missing, setMissing] = useState([])     // grupos del PGC sin subcuenta al aplicar una plantilla
  const [rules, setRules] = useState([])         // cuentas controladas (0036): qué módulo mueve cada cuenta
  const [editing, setEditing] = useState(editId ?? null)   // v0.47.0 · id del borrador que se está editando

  // Solo subcuentas (posting): son las únicas donde se puede apuntar
  const loadAccounts = () => fetchAll(() => supabase.from('gl_accounts').select('id, account_no, name, name_en')
    .eq('company_id', company.id).eq('account_type', 'posting').order('account_no'))
    .then(({ data }) => { setAccounts(data ?? []); return data ?? [] })

  useEffect(() => {
    loadAccounts()
    supabase.from('fiscal_years').select('id, year, starting_date, ending_date, status')
      .eq('company_id', company.id)
      .then(({ data }) => setFiscalYears(data ?? []))
    supabase.from('control_rules').select('account_prefix, modules, side').then(({ data }) => setRules(data ?? []))
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

  // v0.47.0 · Seguir un borrador: su cabecera y sus líneas, tal como se guardaron (aunque estén a medias)
  useEffect(() => {
    if (!editId) return
    Promise.all([
      loadAccounts(),
      supabase.from('journal_entries').select('id, posting_date, description, document_no, status').eq('id', editId).single(),
      supabase.from('journal_lines').select('gl_account_id, debit, credit, description, line_no').eq('entry_id', editId).order('line_no'),
    ]).then(([list, e, l]) => {
      if (e.error || e.data?.status !== 'draft') { setEditing(null); return setError(e.error?.message ?? t('draftNotFound')) }
      const no = (id) => list.find((a) => a.id === id)?.account_no ?? ''
      setHeader({ posting_date: e.data.posting_date, description: e.data.description === 'Borrador' ? '' : e.data.description ?? '', document_no: e.data.document_no ?? '' })
      const ls = (l.data ?? []).map((x) => ({ accountText: no(x.gl_account_id), gl_account_id: x.gl_account_id,
        debit: Number(x.debit) ? String(x.debit) : '', credit: Number(x.credit) ? String(x.credit) : '', description: x.description ?? '' }))
      setLines(ls.length >= 2 ? ls : [...ls, ...Array(2 - ls.length).fill(0).map(emptyLine)])
    })
  }, [editId])   // eslint-disable-line react-hooks/exhaustive-deps

  // Mover el cursor cuando React ya ha dibujado la línea (por ejemplo, una línea nueva)
  useEffect(() => {
    if (!focusTarget) return
    const el = focusTarget.field === 'post' ? postRef.current : linesRef.current?.querySelector(
      `[data-line="${focusTarget.line}"][data-field="${focusTarget.field}"]`)
    el?.focus()
    el?.select?.()
    setFocusTarget(null)
  }, [focusTarget, lines])

  // Totales en céntimos para evitar errores de decimales (0.1 + 0.2 ≠ 0.3 en JavaScript): cents() de entryKeys.js
  const totalDebit = lines.reduce((s, l) => s + cents(l.debit), 0)
  const totalCredit = lines.reduce((s, l) => s + cents(l.credit), 0)
  const difference = totalDebit - totalCredit
  const usedLines = lines.filter((l) => l.gl_account_id && (cents(l.debit) || cents(l.credit)))
  const balanced = difference === 0 && totalDebit > 0 && usedLines.length >= 2

  // CUENTAS CONTROLADAS (v0.33.0): ¿el asiento toca una cuenta que solo mueve su módulo (410, 430, 472…)?
  //   estricto → no se puede contabilizar (la base de datos tampoco lo dejaría): solo borrador
  //   guiado   → se contabiliza, con aviso (y saldrá en Comprobaciones)
  const strict = company.control_mode === 'strict'
  const controlled = controlledLines(usedLines.map((l) => ({
    account_no: accounts.find((a) => a.id === l.gl_account_id)?.account_no, debit: cents(l.debit) / 100, credit: cents(l.credit) / 100,
  })), rules)
  const ctlModules = [...new Set(controlled.flatMap((c) => c.modules))]
  const ctlScreen = moduleScreen(ctlModules)
  const blocked = strict && controlled.length > 0

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

  // Cuentas que encajan con lo escrito: por número (empieza por) o por nombre (contiene), como máximo 8
  function matchAccounts(text) {
    const q = norm(text).trim()
    if (!q || q.includes('.')) return []           // con el atajo del punto no se sugiere: se resuelve con Enter
    const byNumber = /^\d+$/.test(q)
    return accounts.filter((a) => (byNumber
      ? a.account_no.startsWith(q)
      : norm(accountName(a, language)).includes(q) || norm(a.name).includes(q))).slice(0, 8)
  }

  function chooseAccount(i, a) {
    setLines((prev) => {
      const copy = [...prev]
      copy[i] = { ...copy[i], accountText: a.account_no, gl_account_id: a.id }
      return copy
    })
    setSuggest(null)
    setFocusTarget({ line: i, field: lines[i].expect ?? 'debit' })   // al lado que pide la plantilla; si no, al Debe
  }

  // Plantilla: cada línea toma la primera subcuenta de su grupo; los importes quedan para el usuario
  function applyTemplate(tpl) {
    const gaps = []
    setLines(tpl.lines.map((tl) => {
      const a = accounts.find((x) => x.account_no.startsWith(tl.prefix))
      if (!a) gaps.push(tl.prefix)
      return { ...emptyLine(), accountText: a?.account_no ?? tl.prefix, gl_account_id: a?.id ?? '', expect: tl.side, total: Boolean(tl.total) }
    }))
    setMissing(gaps)
    setHeader((h) => ({ ...h, description: t(`tpl.${tpl.id}.concept`) }))
    setError(''); setMessage(t('tplLoaded')); setPostedOk(false); setSuggest(null)
    setFocusTarget({ line: 0, field: tpl.lines[0].side })
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
    const gone = lines[i]
    setLines((prev) => removeLineFrom(prev, i, emptyLine))
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
      if (prev.length === 2 && !prev[index].accountText && !prev[index].debit && !prev[index].credit) copy[index] = line   // se había vaciado
      else copy.splice(index, 0, line)
      return copy
    })
    setRemoved(null)
    setFocusTarget({ line: index, field: 'account' })
  }

  // Pone en la línea el importe propuesto (lo que falta para cuadrar), en su lado
  function fillSuggestion(i, sug) {
    const amount = String(sug.cents / 100).replace('.', ',')
    setLines((prev) => {
      const copy = [...prev]
      copy[i] = { ...copy[i], debit: sug.side === 'debit' ? amount : '', credit: sug.side === 'credit' ? amount : '' }
      return copy
    })
  }

  // A la cuenta de la línea siguiente; después de la última, una línea nueva
  const nextLine = (i) => (i === lines.length - 1 ? addLine(i) : setFocusTarget({ line: i + 1, field: 'account' }))

  // Teclado dentro de una línea
  function onLineKey(e, i, field) {
    const sug = suggestionFor(lines, i)
    const other = lineKeyAction(e, field, sug)
    if (other) {
      e.preventDefault()
      if (other.type === 'remove') return removeLine(i)
      if (other.type === 'add') return addLine(i)
      if (other.type === 'fill') return fillSuggestion(i, sug)
    }
    // "−" borra solo desde el campo de cuenta vacío: en Debe/Haber se escribe como signo
    if (e.key === '-' && field === 'account' && !lines[i].accountText.trim()) {
      e.preventDefault()
      return removeLine(i)
    }
    // Lista de cuentas abierta: ↑ ↓ eligen, Enter confirma, Escape cierra
    if (field === 'account' && suggest?.line === i) {
      const list = matchAccounts(lines[i].accountText)
      if (list.length && (e.key === 'ArrowDown' || e.key === 'ArrowUp')) {
        e.preventDefault()
        const step = e.key === 'ArrowDown' ? 1 : -1
        return setSuggest({ line: i, active: (suggest.active + step + list.length) % list.length })
      }
      if (e.key === 'Escape') return setSuggest(null)
      if (e.key === 'Enter' && list.length && !byNo(lines[i].accountText.trim())) {
        e.preventDefault()
        return chooseAccount(i, list[Math.min(suggest.active, list.length - 1)])
      }
    }
    if (e.key !== 'Enter') return
    e.preventDefault()
    const resolved = field === 'account' && lines[i].accountText.trim() ? resolveAccount(i) : Boolean(lines[i].gl_account_id)
    const act = enterAction({ field, line: lines[i], i, suggestion: sug, balanced, resolved })
    if (act.type === 'focus') setFocusTarget({ line: act.line, field: act.field })
    else if (act.type === 'post') setFocusTarget({ field: 'post' })
    else if (act.type === 'fill') { fillSuggestion(i, sug); nextLine(i) }
    else if (act.type === 'next') nextLine(i)
  }

  async function save(post) {
    setError('')
    setMessage('')
    setPostedOk(false)
    const fy = fiscalYears.find((y) => header.posting_date >= y.starting_date && header.posting_date <= y.ending_date)
    if (!fy) return setError(t('noFiscalYear'))
    // v0.47.0 · Un borrador se puede guardar a medias (una línea, sin cuadrar); para contabilizar, completo
    if (usedLines.length < 1) return setError(t('needOneLine'))
    if (post && !header.description.trim()) return setError(t('needDescription'))
    if (post && usedLines.length < 2) return setError(t('needTwoLines'))
    if (post && !balanced) return setError(t('unbalanced'))

    setSaving(true)
    const payloadLines = usedLines.map((l) => ({ gl_account_id: l.gl_account_id, debit: cents(l.debit) / 100, credit: cents(l.credit) / 100,
      description: l.description || null }))
    // 1) El borrador (nuevo o el que se está editando): erp.save_draft, 0070
    let { data: id, error: e1 } = await supabase.rpc('save_draft', { p: { company_id: company.id, entry_id: editing, posting_date: header.posting_date,
      description: header.description, document_no: header.document_no || null, lines: payloadLines } })
    if (e1?.code === 'PGRST202' && !editing) {
      // Sin la migración 0070: como antes, cabecera y líneas por separado
      const { data: entry, error: ea } = await supabase.from('journal_entries')
        .insert({ ...header, description: header.description || 'Borrador', document_no: header.document_no || null, company_id: company.id, fiscal_year_id: fy.id })
        .select('id').single()
      if (ea) { setSaving(false); return setError(ea.message) }
      const { error: eb } = await supabase.from('journal_lines').insert(payloadLines.map((l, i) => ({ ...l, entry_id: entry.id, company_id: company.id, line_no: i + 1 })))
      if (eb) { setSaving(false); return setError(eb.message) }
      id = entry.id; e1 = null
    }
    if (e1) { setSaving(false); return setError(e1.message) }
    setEditing(id)

    // 2) Contabilizar (la base de datos vuelve a validar el cuadre y el periodo). Si falla, el borrador queda guardado.
    if (post) {
      const { data: entryNo, error: e3 } = await supabase.rpc('post_entry', { p_entry: id })
      setSaving(false)
      if (e3) return setError(e3.message)
      setMessage(t('postedAs').replace('{n}', entryNo))
      setPostedOk(true)
    } else {
      setSaving(false)
      setMessage(t('savedDraft'))
    }
    setEditing(null)
    setHeader({ posting_date: header.posting_date, description: '', document_no: '' })
    setLines([emptyLine(), emptyLine()])
    setMissing([])
    onPosted?.()
    if (editId) navigate(companyPath(company.id, 'entry'), { replace: true })
  }

  const tax = company.tax_territory === 'canary_islands' ? 'IGIC' : 'IVA'
  const screenLabel = (id) => t(`nav.${id}.label`).replace('{tax}', tax).replace('{form}', tax === 'IGIC' ? '420' : '303')

  return (
    <section className="tarjeta formulario-asiento">
      <h2>{editing ? t('editDraft') : t('newEntry')}</h2>
      {editing && <p className="ayuda">✎ {t('editDraftHelp')} <Link to={companyPath(company.id, 'entries')} className="enlace">{t('nav.entries.label')} →</Link></p>}

      <div className="rejilla-cabecera cabecera-asiento">
        <label>{t('postingDate')}
          <DateField value={header.posting_date} company={company} id="asiento-fecha"
                     onChange={(d) => setHeader((h) => ({ ...h, posting_date: d }))} />
        </label>
        <label>{t('documentNo')}
          <input value={header.document_no} onChange={(e) => setHeader({ ...header, document_no: e.target.value })} />
        </label>
        <label className="concepto-asiento">{t('entryConcept')}
          <input placeholder={t('entryDescription')} value={header.description}
                 onChange={(e) => setHeader({ ...header, description: e.target.value })} />
        </label>
      </div>

      {/* ¿Qué ha pasado? Plantillas de los asientos más frecuentes */}
      <div className="plantillas">
        <span className="plantillas-titulo">{t('tplTitle')}</span>
        <div className="plantillas-botones">
          {TEMPLATES.map((tpl) => (
            <button key={tpl.id} type="button" className="secundario" onClick={() => applyTemplate(tpl)}>
              <tpl.icon {...ICON} /> {t(`tpl.${tpl.id}.label`)}
            </button>
          ))}
        </div>
        <p className="ayuda">
          {t('tplNote').replace('{tax}', tax)}{' '}
          <Link to={companyPath(company.id, 'invoices')} className="enlace">{t('homeQuickInvoice')} →</Link>
        </p>
      </div>
      {missing.length > 0 && (
        <p className="aviso">
          {t('tplMissing').replace('{g}', missing.join(', '))}{' '}
          <Link to={companyPath(company.id, missing.some((g) => g === '400' || g === '430') ? 'partners' : 'accounts')} className="enlace">
            {t(missing.some((g) => g === '400' || g === '430') ? 'actionAddPartner' : 'actionOpenChart')} →
          </Link>
        </p>
      )}

      {accounts.length === 0 && (
        <p className="aviso">{t('noPostingAccounts')} <Link to={companyPath(company.id, 'accounts')} className="enlace">{t('actionOpenChart')} →</Link></p>
      )}
      <p className="ayuda">⌨ {t('keyboardHelp')}</p>
      <details className="explica">
        <summary>{t('explainDebitTitle')}</summary>
        <p>{t('explainDebit')}</p>
      </details>
      <details className="explica">
        <summary>{t('explainDraftTitle')}</summary>
        <p>{t('explainDraft')}</p>
      </details>

      <div ref={linesRef} className="lineas-asiento">
        <div className="linea cabecera-lineas" aria-hidden="true">
          <span>{t('account')}</span><span>{t('debit')}</span><span>{t('credit')}</span><span />
        </div>
        {lines.map((l, i) => {
          const account = accounts.find((a) => a.id === l.gl_account_id)
          const unknown = l.accountText.trim() !== '' && !account
          const options = suggest?.line === i && !account ? matchAccounts(l.accountText) : []
          const listId = `cuentas-${i}`
          const sug = suggestionFor(lines, i)
          // Importe propuesto (lo que falta para cuadrar), en gris en su lado: Enter o «=» lo ponen
          const hint = (side) => (sug?.side === side ? `= ${money(sug.cents / 100, language)}` : t(side))
          return (
            <div key={i} className={l.total ? 'linea linea-total' : 'linea'}>
              <div className="cuenta-linea">
                <input
                  data-line={i} data-field="account" role="combobox" aria-autocomplete="list"
                  aria-expanded={options.length > 0} aria-controls={listId} aria-label={t('account')}
                  aria-activedescendant={options.length ? `${listId}-${Math.min(suggest.active, options.length - 1)}` : undefined}
                  placeholder={t('accountSearch')} value={l.accountText} autoComplete="off"
                  className={unknown ? 'invalido' : ''}
                  onChange={(e) => { updateLine(i, 'accountText', e.target.value); setSuggest({ line: i, active: 0 }) }}
                  onKeyDown={(e) => onLineKey(e, i, 'account')}
                  onBlur={() => { setSuggest(null); if (l.accountText && !l.gl_account_id) resolveAccount(i) }} />
                {options.length > 0 && (
                  <ul id={listId} role="listbox" className="sugerencias">
                    {options.map((a, k) => (
                      <li key={a.id} id={`${listId}-${k}`} role="option" aria-selected={k === suggest.active}
                          className={k === suggest.active ? 'activa' : ''}
                          onMouseDown={(e) => { e.preventDefault(); chooseAccount(i, a) }}>
                        <span className="codigo">{a.account_no}</span> {accountName(a, language)}
                      </li>
                    ))}
                  </ul>
                )}
                <span className={unknown ? 'nombre-cuenta aviso' : 'nombre-cuenta'}>
                  {account ? accountName(account, language) : unknown ? t('accountNotFound') : ''}
                </span>
              </div>
              <input data-line={i} data-field="debit" placeholder={hint('debit')} inputMode="decimal" value={l.debit}
                     aria-label={t('debit')} title={sug?.side === 'debit' ? t('suggestedAmount') : undefined}
                     className={[l.expect === 'debit' ? 'esperado' : '', sug?.side === 'debit' ? 'propuesto' : ''].join(' ').trim()}
                     onChange={(e) => updateLine(i, 'debit', e.target.value)}
                     onKeyDown={(e) => onLineKey(e, i, 'debit')} />
              <input data-line={i} data-field="credit" placeholder={hint('credit')} inputMode="decimal" value={l.credit}
                     aria-label={t('credit')} title={sug?.side === 'credit' ? t('suggestedAmount') : undefined}
                     className={[l.expect === 'credit' ? 'esperado' : '', sug?.side === 'credit' ? 'propuesto' : ''].join(' ').trim()}
                     onChange={(e) => updateLine(i, 'credit', e.target.value)}
                     onKeyDown={(e) => onLineKey(e, i, 'credit')} />
              <button type="button" className="papelera" tabIndex={-1} onClick={() => removeLine(i)}
                      title={t('removeLineKey')} aria-label={`${t('removeLine')} ${i + 1}`}>
                <Trash2 size={16} aria-hidden="true" />
              </button>
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
        <span><Term id="debit">{t('debit')}</Term>: <strong>{money(totalDebit / 100, language)}</strong></span>
        <span><Term id="credit">{t('credit')}</Term>: <strong>{money(totalCredit / 100, language)}</strong></span>
        <span>{balanced ? `✓ ${t('balanced')}` : `${t('difference')}: ${money(difference / 100, language)}`}</span>
      </div>

      {controlled.length > 0 && (
        <div className={blocked ? 'aviso-controlada estricto' : 'aviso-controlada'} role="status">
          <p className="aviso-controlada-titulo">
            {blocked ? '⛔' : '⚠'} {t(blocked ? 'ctl.strictTitle' : 'ctl.guidedTitle')
              .replace('{a}', [...new Set(controlled.map((c) => c.account_no))].join(', '))}{' '}
            <Term id="controlledAccount">{t('ctl.what')}</Term>
          </p>
          <p>{t(blocked ? 'ctl.strictHelp' : 'ctl.guidedHelp')
              .replace('{m}', ctlModules.map((m) => t(`ctl.module.${m}`)).join(t('ctl.or')))}</p>
          <Link to={companyPath(company.id, ctlScreen)} className="boton secundario">{t('err.goTo')} {screenLabel(ctlScreen)} →</Link>
        </div>
      )}

      <div className="fila">
        <button type="button" className="secundario" disabled={saving} onClick={() => save(false)}>{t('saveDraft')}</button>
        <button type="button" ref={postRef} disabled={saving || !balanced || blocked} title={blocked ? t('ctl.postDisabled') : undefined}
                onClick={() => save(true)}>{t('post')}</button>
      </div>

      <ErrorBox error={error} company={company} />
      {message && (
        <p className="exito">✓ {message}
          {postedOk && <> · <Link to={companyPath(company.id, 'journal')} className="enlace">{t('seeInJournal')} →</Link></>}
        </p>
      )}
    </section>
  )
}
