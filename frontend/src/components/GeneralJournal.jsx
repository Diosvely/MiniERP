import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { money } from '../format'

const yearStart = () => `${new Date().getFullYear()}-01-01`

// Libro diario: asientos contabilizados entre dos fechas, con búsqueda y anulación (contraasiento)
//   como el "Diario entre fechas" de A3 y "Reverse Transaction" de Business Central / FB08 de SAP
export default function GeneralJournal({ company, readOnly, refreshKey }) {
  const { t, language } = useI18n()
  const [rows, setRows] = useState([])
  const [from, setFrom] = useState(yearStart())
  const [to, setTo] = useState('')
  const [search, setSearch] = useState('')
  const [reversing, setReversing] = useState(null)      // { entry_id, date, reason }
  const [reload, setReload] = useState(0)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')

  useEffect(() => {
    let q = supabase.from('v_general_journal').select('*').eq('company_id', company.id)
    if (from) q = q.gte('posting_date', from)
    if (to) q = q.lte('posting_date', to)
    q.order('posting_date').order('entry_no').order('line_no')
      .then(({ data, error }) => (error ? setError(error.message) : setRows(data)))
  }, [company.id, from, to, refreshKey, reload])

  // Agrupar las líneas por asiento
  const entries = []
  for (const r of rows) {
    const last = entries[entries.length - 1]
    if (last && last.entry_id === r.entry_id) last.lines.push(r)
    else entries.push({ ...r, lines: [r] })
  }

  // Búsqueda: concepto, nº de documento, nº de asiento o cuenta
  const q = search.trim().toLowerCase()
  const visible = entries.filter((e) => !q
    || (e.entry_description ?? '').toLowerCase().includes(q)
    || (e.document_no ?? '').toLowerCase().includes(q)
    || String(e.entry_no) === q
    || e.lines.some((l) => l.account_no.startsWith(q)))

  const name = (r) => (language === 'en' ? r.account_name_en || r.account_name : r.account_name)
  const sum = (field) => visible.reduce((s, e) => s + e.lines.reduce((x, l) => x + Number(l[field]), 0), 0)

  async function reverse() {
    setError(''); setMessage('')
    const { data, error } = await supabase.rpc('reverse_entry', {
      p_entry: reversing.entry_id, p_posting_date: reversing.date, p_reason: reversing.reason || null,
    })
    if (error) return setError(error.message)
    setMessage(t('entryReversed').replace('{n}', reversing.entry_no).replace('{m}', data))
    setReversing(null); setReload((k) => k + 1)
  }

  return (
    <section className="tarjeta">
      <h2>{t('generalJournal')}</h2>
      <div className="rejilla-tres">
        <label>{t('fromDate')}<input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></label>
        <label>{t('toDate')}<input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></label>
        <label>{t('search')}<input value={search} placeholder={t('searchJournal')} onChange={(e) => setSearch(e.target.value)} /></label>
      </div>
      <p className="ayuda">
        {t('entriesShown').replace('{n}', visible.length)} · {t('debit')} {money(sum('debit'), language)} · {t('credit')} {money(sum('credit'), language)}
      </p>
      {error && <p className="aviso">⚠ {error}</p>}
      {message && <p className="exito">✓ {message}</p>}
      {visible.length === 0 && <p>{t('noEntries')}</p>}

      {visible.map((e) => {
        const canReverse = !readOnly && e.source === 'manual' && !e.reversed_by_no
        return (
          <article key={e.entry_id} className={e.reversed_by_no ? 'asiento anulado' : 'asiento'}>
            <header>
              <strong>{t('entry')} {e.entry_no}</strong>
              <span>{e.posting_date}{e.document_no ? ` · ${e.document_no}` : ''}</span>
            </header>
            <div className="etiquetas">
              {e.source === 'invoice' && <span className="etiqueta">{t('sourceInvoice')}</span>}
              {e.source === 'settlement' && <span className="etiqueta">{t('sourceSettlement')}</span>}
              {e.reversal_of_no && <span className="etiqueta anula">↩ {t('reversesEntry').replace('{n}', e.reversal_of_no)}</span>}
              {e.reversed_by_no && <span className="etiqueta anulado">✕ {t('reversedByEntry').replace('{n}', e.reversed_by_no)}</span>}
            </div>
            <p className="concepto">{e.entry_description}</p>
            <table>
              <thead>
                <tr><th>{t('account')}</th><th className="num">{t('debit')}</th><th className="num">{t('credit')}</th></tr>
              </thead>
              <tbody>
                {e.lines.map((l) => (
                  <tr key={l.line_no}>
                    <td><span className="codigo">{l.account_no}</span> {name(l)}</td>
                    <td className="num">{Number(l.debit) ? money(l.debit, language) : ''}</td>
                    <td className="num">{Number(l.credit) ? money(l.credit, language) : ''}</td>
                  </tr>
                ))}
              </tbody>
            </table>

            {canReverse && reversing?.entry_id !== e.entry_id && (
              <button type="button" className="secundario pequeno"
                      onClick={() => setReversing({ entry_id: e.entry_id, entry_no: e.entry_no, date: e.posting_date, reason: '' })}>
                ↩ {t('reverseEntry')}
              </button>
            )}
            {reversing?.entry_id === e.entry_id && (
              <div className="anular">
                <p className="ayuda">{t('reverseHelp')}</p>
                <div className="rejilla-cabecera">
                  <label>{t('reversalDate')}
                    <input type="date" value={reversing.date} min={e.posting_date}
                           onChange={(ev) => setReversing({ ...reversing, date: ev.target.value })} />
                  </label>
                  <label>{t('reversalReason')}
                    <input value={reversing.reason} onChange={(ev) => setReversing({ ...reversing, reason: ev.target.value })} />
                  </label>
                </div>
                <div className="fila">
                  <button type="button" className="secundario" onClick={() => setReversing(null)}>{t('cancel')}</button>
                  <button type="button" onClick={reverse}>{t('confirmReverse')}</button>
                </div>
              </div>
            )}
          </article>
        )
      })}
    </section>
  )
}