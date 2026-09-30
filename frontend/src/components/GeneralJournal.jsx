import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { money } from '../format'

// Libro diario: asientos contabilizados agrupados por número
export default function GeneralJournal({ company, refreshKey }) {
  const { t, language } = useI18n()
  const [rows, setRows] = useState([])
  const [error, setError] = useState('')

  useEffect(() => {
    supabase.from('v_general_journal').select('*')
      .eq('company_id', company.id)
      .order('fiscal_year').order('entry_no').order('line_no')
      .then(({ data, error }) => (error ? setError(error.message) : setRows(data)))
  }, [company.id, refreshKey])

  // Agrupar las líneas por asiento
  const entries = []
  for (const r of rows) {
    const last = entries[entries.length - 1]
    if (last && last.entry_id === r.entry_id) last.lines.push(r)
    else entries.push({ ...r, lines: [r] })
  }

  const name = (r) => (language === 'en' ? r.account_name_en || r.account_name : r.account_name)

  return (
    <section className="tarjeta">
      <h2>{t('generalJournal')}</h2>
      {error && <p className="aviso">⚠ {error}</p>}
      {entries.length === 0 && <p>{t('noEntries')}</p>}
      {entries.map((e) => (
        <article key={e.entry_id} className="asiento">
          <header>
            <strong>{t('entry')} {e.entry_no}</strong>
            <span>{e.posting_date}{e.document_no ? ` · ${e.document_no}` : ''}</span>
          </header>
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
        </article>
      ))}
    </section>
  )
}