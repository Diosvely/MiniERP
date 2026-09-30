import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { accountName, money } from '../format'

const today = () => new Date().toISOString().slice(0, 10)
const emptyLine = () => ({ gl_account_id: '', debit: '', credit: '', description: '' })

// Formulario de asiento: cabecera + líneas, con cuadre en vivo
export default function JournalEntryForm({ company, onPosted }) {
  const { t, language } = useI18n()
  const [accounts, setAccounts] = useState([])
  const [fiscalYears, setFiscalYears] = useState([])
  const [header, setHeader] = useState({ posting_date: today(), description: '', document_no: '' })
  const [lines, setLines] = useState([emptyLine(), emptyLine()])
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    // Solo subcuentas (posting): son las únicas donde se puede apuntar
    supabase.from('gl_accounts').select('id, account_no, name, name_en')
      .eq('company_id', company.id).eq('account_type', 'posting').order('account_no')
      .then(({ data }) => setAccounts(data ?? []))
    supabase.from('fiscal_years').select('id, year, starting_date, ending_date, status')
      .eq('company_id', company.id)
      .then(({ data }) => setFiscalYears(data ?? []))
  }, [company.id])

  // Totales en céntimos para evitar errores de decimales (0.1 + 0.2 ≠ 0.3 en JavaScript)
  const cents = (v) => Math.round((parseFloat(String(v).replace(',', '.')) || 0) * 100)
  const totalDebit = lines.reduce((s, l) => s + cents(l.debit), 0)
  const totalCredit = lines.reduce((s, l) => s + cents(l.credit), 0)
  const difference = totalDebit - totalCredit
  const usedLines = lines.filter((l) => l.gl_account_id && (cents(l.debit) || cents(l.credit)))
  const balanced = difference === 0 && totalDebit > 0 && usedLines.length >= 2

  function updateLine(i, field, value) {
    const copy = [...lines]
    copy[i] = { ...copy[i], [field]: value }
    // Un apunte va al Debe O al Haber: si escribes en uno, se vacía el otro
    if (field === 'debit' && value) copy[i].credit = ''
    if (field === 'credit' && value) copy[i].debit = ''
    setLines(copy)
  }

  // Pone en la línea la diferencia que falta para cuadrar
  function fillDifference(i) {
    const copy = [...lines]
    const others = (field) => lines.reduce((s, l, j) => (j === i ? s : s + cents(l[field])), 0)
    const diff = others('debit') - others('credit')
    copy[i] = { ...copy[i], debit: diff < 0 ? String(-diff / 100) : '', credit: diff > 0 ? String(diff / 100) : '' }
    setLines(copy)
  }

  async function save(post) {
    setError('')
    setMessage('')
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
    } else {
      setSaving(false)
      setMessage(t('savedDraft'))
    }
    setHeader({ posting_date: header.posting_date, description: '', document_no: '' })
    setLines([emptyLine(), emptyLine()])
    onPosted?.()
  }

  return (
    <section className="tarjeta">
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

      {accounts.length === 0 && <p className="aviso">{t('noPostingAccounts')}</p>}

      {lines.map((l, i) => (
        <div key={i} className="linea">
          <select value={l.gl_account_id} onChange={(e) => updateLine(i, 'gl_account_id', e.target.value)}>
            <option value="">{t('selectAccount')}</option>
            {accounts.map((a) => (
              <option key={a.id} value={a.id}>{a.account_no} · {accountName(a, language)}</option>
            ))}
          </select>
          <input placeholder={t('debit')} inputMode="decimal" value={l.debit}
                 onChange={(e) => updateLine(i, 'debit', e.target.value)} />
          <input placeholder={t('credit')} inputMode="decimal" value={l.credit}
                 onChange={(e) => updateLine(i, 'credit', e.target.value)} />
          <div className="acciones-linea">
            <button type="button" className="secundario" onClick={() => fillDifference(i)} title={t('fillDifference')}>=</button>
            <button type="button" className="secundario" disabled={lines.length <= 2}
                    onClick={() => setLines(lines.filter((_, j) => j !== i))} title={t('removeLine')}>✕</button>
          </div>
        </div>
      ))}

      <button type="button" className="secundario" onClick={() => setLines([...lines, emptyLine()])}>
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
      {message && <p className="exito">✓ {message}</p>}
    </section>
  )
}