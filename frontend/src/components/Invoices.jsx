import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { money, shortDate } from '../format'
import { companyPath } from '../router'
import Link from './Link'
import InvoiceForm from './InvoiceForm'
import Empty from './Empty'
import ErrorBox from './ErrorBox'

// Facturas recibidas y emitidas: formulario de registro + libro registro
export default function Invoices({ company, readOnly }) {
  const { t, language } = useI18n()
  const [invoiceType, setInvoiceType] = useState('purchase')
  const [invoices, setInvoices] = useState([])
  const [open, setOpen] = useState({})   // estado de cobro / pago de cada factura (partidas abiertas, 0035)
  const [error, setError] = useState('')

  async function load() {
    const { data, error } = await supabase.from('v_invoices').select('*')
      .eq('company_id', company.id).eq('invoice_type', invoiceType)
      .order('posting_date', { ascending: false }).order('invoice_no', { ascending: false })
    if (error) setError(error.message)
    else { setError(''); setInvoices(data) }
    // Si la 0035 aún no está en Supabase, la lista se ve igual, solo que sin el estado
    const o = await supabase.rpc('open_items', { p_company: company.id })
    if (!o.error) setOpen(Object.fromEntries((o.data ?? []).map((x) => [x.invoice_id, x])))
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
                {' · '}{t('entry')} <Link to={companyPath(company.id, `asiento/${i.fiscal_year}/${i.entry_no}`)} className="num-asiento">{i.entry_no}</Link>
                {i.document_kind === 'credit_memo' && ` · ${t('corrects')} ${i.corrected_reference ?? i.corrected_invoice_no ?? '—'}`}
              </span>
              {open[i.id] && <InvoiceStatus item={open[i.id]} type={invoiceType} company={company} t={t} language={language} />}
            </li>
          ))}
        </ul>
      </section>
    </>
  )
}

// Estado de la factura: cobrada / pagada, parcial o pendiente (con vencimiento); enlace a Cobros y pagos
function InvoiceStatus({ item, type, company, t, language }) {
  const paid = item.status === 'paid'
  const label = t(`invStatus.${item.status}.${type}`)
  return (
    <span className={`estado-factura ${item.status}`}>
      <span className="insignia">{label}</span>
      {!paid && <> {t('pay.pending')}: <strong>{money(item.pending, language)}</strong> · {t('invStatus.due')} {shortDate(item.due_date)}
        {item.days_overdue > 0 && <span className="vencida"> · {t('pay.overdue').replace('{d}', item.days_overdue)}</span>}
        {' · '}<Link to={companyPath(company.id, 'payments')} className="enlace">{t(type === 'purchase' ? 'invStatus.toPay' : 'invStatus.toCollect')} →</Link></>}
    </span>
  )
}
