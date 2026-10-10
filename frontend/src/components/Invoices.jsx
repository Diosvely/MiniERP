import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { money } from '../format'
import InvoiceForm from './InvoiceForm'
import Empty from './Empty'
import ErrorBox from './ErrorBox'

// Facturas recibidas y emitidas: formulario de registro + libro registro
export default function Invoices({ company, readOnly }) {
  const { t, language } = useI18n()
  const [invoiceType, setInvoiceType] = useState('purchase')
  const [invoices, setInvoices] = useState([])
  const [error, setError] = useState('')

  async function load() {
    const { data, error } = await supabase.from('v_invoices').select('*')
      .eq('company_id', company.id).eq('invoice_type', invoiceType)
      .order('posting_date', { ascending: false }).order('invoice_no', { ascending: false })
    if (error) setError(error.message)
    else { setError(''); setInvoices(data) }
  }

  useEffect(() => { load() }, [company.id, invoiceType])

  return (
    <>
      <nav className="pestanas">
        {['purchase', 'sale'].map((ty) => (
          <button key={ty} type="button" className={invoiceType === ty ? 'activa' : ''} onClick={() => setInvoiceType(ty)}>
            {t(`invoiceTypePlural.${ty}`)}
          </button>
        ))}
      </nav>

      {!readOnly && <InvoiceForm company={company} invoiceType={invoiceType} invoices={invoices} onPosted={load} />}

      <section className="tarjeta">
        <h2>{t(`invoiceRegister.${invoiceType}`)} ({invoices.length})</h2>
        <ErrorBox error={error} company={company} />
        {invoices.length === 0 && (
          <Empty icon="🧾" text={t('noInvoices')} help={readOnly ? null : t('emptyInvoicesHelp')} />
        )}
        <ul>
          {invoices.map((i) => (
            <li key={i.id}>
              <strong>
                <span className="codigo">{i.invoice_no}</span>
                {i.external_document_no && `${i.external_document_no} · `}{i.partner_name}
                {i.document_kind === 'credit_memo' && <span className="insignia">{t('kind.credit_memo')}</span>}
              </strong>
              <span>
                {i.invoice_date} · {t('taxBase')} {money(i.total_base, language)} · {t('taxAmount')} {money(i.total_tax, language)}
                {' · '}<strong>{money(i.total_amount, language)}</strong>
                {Number(i.withholding_amount) !== 0 && ` · ${t('withholding')} ${money(i.withholding_amount, language)} · ${invoiceType === 'purchase' ? t('amountToPay') : t('amountToCollect')} ${money(i.amount_due, language)}`}
                {' · '}{t('entry')} {i.entry_no}
                {i.document_kind === 'credit_memo' && ` · ${t('corrects')} ${i.corrected_reference ?? i.corrected_invoice_no ?? '—'}`}
              </span>
            </li>
          ))}
        </ul>
      </section>
    </>
  )
}
