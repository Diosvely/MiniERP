import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { money } from '../format'
import { companyPath } from '../router'
import Link from './Link'
import Loading from './Loading'
import ErrorBox from './ErrorBox'

// FICHA DE UN ASIENTO: se llega desde el nº de asiento del libro mayor (#/empresa/<id>/asiento/<año>/<nº>).
// Es el "rastro contable" que siguen los ERP: en SAP, del mayor (FBL3N) se abre el documento (FB03) con doble clic;
// en Business Central, desde los movimientos de una cuenta se "navega" al asiento y a su documento.
// Desde aquí se sigue el rastro: cada cuenta lleva a SU libro mayor, y una anulación lleva a su asiento pareja.
// Se identifica por ejercicio + nº de asiento, igual que en SAP (sociedad + nº de documento + ejercicio).
export default function EntryDetail({ company, year, entryNo }) {
  const { t, language } = useI18n()
  const [lines, setLines] = useState(null)
  const [error, setError] = useState('')

  useEffect(() => {
    let alive = true
    supabase.from('v_general_journal').select('*')
      .eq('company_id', company.id).eq('fiscal_year', Number(year)).eq('entry_no', Number(entryNo))
      .order('line_no')
      .then(({ data, error }) => {
        if (!alive) return
        if (error) return setError(error.message)
        setLines(data ?? [])
      })
    return () => { alive = false }
  }, [company.id, year, entryNo])

  const m = (v) => money(v, language)
  const name = (l) => (language === 'en' ? l.account_name_en || l.account_name : l.account_name)
  const back = () => window.history.back()

  if (error) return <ErrorBox error={error} company={company} />
  if (!lines) return <Loading />
  if (lines.length === 0) {
    return (
      <section className="tarjeta">
        <p className="aviso">⚠ {t('entryNotFound').replace('{n}', entryNo).replace('{y}', year)}</p>
        <button type="button" className="secundario" onClick={back}>← {t('goBack')}</button>
      </section>
    )
  }

  const e = lines[0]
  const debit = lines.reduce((s, l) => s + Number(l.debit), 0)
  const credit = lines.reduce((s, l) => s + Number(l.credit), 0)
  // La columna Concepto solo sale si alguna línea tiene un texto distinto al del asiento
  const lineText = lines.some((l) => l.description !== e.entry_description)
  const ledger = (account) => companyPath(company.id, `reports/mayor/${account}/${year}`)
  const entryLink = (n) => companyPath(company.id, `asiento/${year}/${n}`)
  const date = new Date(`${e.posting_date}T00:00:00`).toLocaleDateString(language === 'en' ? 'en-GB' : 'es-ES')

  return (
    <section className={e.reversed_by_no ? 'tarjeta ficha-asiento anulado' : 'tarjeta ficha-asiento'}>
      <div className="ficha-cabecera">
        <h2>{t('entry')} {e.entry_no} · {year}</h2>
        <button type="button" className="secundario" onClick={back}>← {t('goBack')}</button>
      </div>
      <dl className="ficha-datos">
        <div><dt>{t('date')}</dt><dd>{date}</dd></div>
        <div><dt>{t('description')}</dt><dd>{e.entry_description}</dd></div>
        {e.document_no && <div><dt>{t('documentNo')}</dt><dd>{e.document_no}</dd></div>}
      </dl>
      <div className="etiquetas">
        {e.source === 'invoice' && <span className="etiqueta">{t('sourceInvoice')}</span>}
        {e.source === 'settlement' && <span className="etiqueta">{t('sourceSettlement')}</span>}
        {e.source === 'payment' && <span className="etiqueta">{t('sourcePayment')}</span>}
        {e.source === 'closing' && <span className="etiqueta">🔒 {t('sourceClosing')}</span>}
        {/* La pareja de una anulación suele estar en el mismo ejercicio; si no, la ficha avisa de que no la encuentra */}
        {e.reversal_of_no && (
          <Link to={entryLink(e.reversal_of_no)} className="etiqueta anula">↩ {t('reversesEntry').replace('{n}', e.reversal_of_no)}</Link>
        )}
        {e.reversed_by_no && (
          <Link to={entryLink(e.reversed_by_no)} className="etiqueta anulado">✕ {t('reversedByEntry').replace('{n}', e.reversed_by_no)}</Link>
        )}
        {e.reversal_reason && <span className="etiqueta">{e.reversal_reason}</span>}
      </div>

      <div className="tabla-scroll">
        <table className="informe">
          <thead>
            <tr><th>{t('account')}</th>{lineText && <th>{t('description')}</th>}<th className="num">{t('debit')}</th><th className="num">{t('credit')}</th></tr>
          </thead>
          <tbody>
            {lines.map((l) => (
              <tr key={l.line_no}>
                <td>
                  <Link to={ledger(l.account_no)} className="enlace" title={t('openLedger')}>
                    <span className="codigo">{l.account_no}</span> {name(l)}
                  </Link>
                </td>
                {lineText && <td>{l.description !== e.entry_description ? l.description : ''}</td>}
                <td className="num">{Number(l.debit) ? m(l.debit) : ''}</td>
                <td className="num">{Number(l.credit) ? m(l.credit) : ''}</td>
              </tr>
            ))}
            <tr className="total">
              <td colSpan={lineText ? 2 : 1}>{t('total')} {Math.round(debit * 100) === Math.round(credit * 100) ? '✓' : '⚠'}</td>
              <td className="num">{m(debit)}</td><td className="num">{m(credit)}</td>
            </tr>
          </tbody>
        </table>
      </div>
      <p className="ayuda">{t('entryDetailHelp')}</p>
    </section>
  )
}
