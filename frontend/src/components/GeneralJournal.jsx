import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { fetchAll } from '../paging'
import { useI18n } from '../i18n'
import { workMonthStart } from '../workDate'
import { money, shortDate } from '../format'
import Empty from './Empty'
import { companyPath } from '../router'
import ErrorBox from './ErrorBox'
import ReportActions from './ReportActions'
import { downloadXlsx, fileName } from '../exportXlsx'
import Link from './Link'


// Libro diario: asientos contabilizados entre dos fechas, con búsqueda y anulación (contraasiento)
//   como el "Diario entre fechas" de A3 y "Reverse Transaction" de Business Central / FB08 de SAP
export default function GeneralJournal({ company, readOnly, refreshKey }) {
  const { t, language } = useI18n()
  const [rows, setRows] = useState([])
  const [from, setFrom] = useState(() => workMonthStart(company))   // desde el día 1 del mes de la fecha de trabajo
  const [to, setTo] = useState('')
  const [search, setSearch] = useState('')
  const [reversing, setReversing] = useState(null)      // { entry_id, date, reason }
  const [reload, setReload] = useState(0)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')

  // Por páginas: un año de una empresa importada tiene miles de apuntes (Supabase da 1.000 por consulta)
  useEffect(() => {
    let alive = true
    fetchAll(() => {
      let q = supabase.from('v_general_journal').select('*').eq('company_id', company.id)
      if (from) q = q.gte('posting_date', from)
      if (to) q = q.lte('posting_date', to)
      return q.order('posting_date').order('entry_no').order('line_no')
    }).then(({ data, error }) => {
      if (!alive) return
      if (error) return setError(error.message)
      setRows(data)
    })
    return () => { alive = false }
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

  // Excel: una fila por apunte de los asientos visibles (con el filtro y la búsqueda aplicados)
  const range = [from && `${t('fromDate')} ${from}`, to && `${t('toDate')} ${to}`, q && `"${search.trim()}"`].filter(Boolean).join(' · ')
  const exportExcel = () => downloadXlsx({
    title: `${t('generalJournal')} · ${company.name}`, subtitle: range, sheet: t('generalJournal'),
    file: fileName(t('generalJournal'), company.name, from, to),
    columns: [
      { header: t('date'), key: 'date', type: 'date', width: 12 },
      { header: t('entry'), key: 'entry', type: 'int', width: 9 },
      { header: t('documentNo'), key: 'doc', type: 'text', width: 16 },
      { header: t('account'), key: 'account', type: 'text', width: 12 },
      { header: t('accountName'), key: 'name', type: 'text', width: 36 },
      { header: t('description'), key: 'desc', type: 'text', width: 44 },
      { header: t('debit'), key: 'debit', type: 'money' },
      { header: t('credit'), key: 'credit', type: 'money' },
    ],
    rows: visible.flatMap((e) => e.lines.map((l) => ({
      date: e.posting_date, entry: e.entry_no, doc: e.document_no, account: l.account_no, name: name(l),
      desc: l.description ?? e.entry_description, debit: Number(l.debit) || null, credit: Number(l.credit) || null,
    }))),
  })

  return (
    <section className="tarjeta">
      <div className="titulo-informe">
        <h2>{t('generalJournal')}</h2>
        {visible.length > 0 && <ReportActions onExcel={exportExcel} info={`${company.name}${range ? ` · ${range}` : ''}`} />}
      </div>
      <div className="rejilla-tres">
        <label>{t('fromDate')}<input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></label>
        <label>{t('toDate')}<input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></label>
        <label>{t('search')}<input value={search} placeholder={t('searchJournal')} onChange={(e) => setSearch(e.target.value)} /></label>
      </div>
      <p className="ayuda">
        {t('entriesShown').replace('{n}', visible.length)} · {t('debit')} {money(sum('debit'), language)} · {t('credit')} {money(sum('credit'), language)}
      </p>
      <ErrorBox error={error} company={company} />
      {message && <p className="exito">✓ {message}</p>}
      {visible.length === 0 && (
        <Empty icon="📒" text={t('noEntries')} action={readOnly ? null : t('actionNewEntry')}
               to={companyPath(company.id, readOnly ? null : 'entry')} />
      )}

      {visible.map((e) => {
        const canReverse = !readOnly && e.source === 'manual' && !e.reversed_by_no
        return (
          <article key={e.entry_id} className={e.reversed_by_no ? 'asiento anulado' : 'asiento'}>
            <header>
              <strong>{t('entry')} {e.entry_no}</strong>
              <span>{shortDate(e.posting_date)}{e.document_no ? ` · ${e.document_no}` : ''}</span>
            </header>
            <div className="etiquetas">
              {e.source === 'invoice' && <span className="etiqueta">{t('sourceInvoice')}</span>}
              {e.source === 'settlement' && <span className="etiqueta">{t('sourceSettlement')}</span>}
              {e.source === 'payment' && <span className="etiqueta">{t('sourcePayment')}</span>}
              {e.source === 'closing' && <span className="etiqueta">🔒 {t('sourceClosing')}</span>}
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
                    <td>
                      <Link to={companyPath(company.id, `reports/mayor/${l.account_no}/${e.fiscal_year}`)} className="enlace" title={t('openLedger')}>
                        <span className="codigo">{l.account_no}</span> {name(l)}
                      </Link>
                    </td>
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
