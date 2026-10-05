import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { accountName, money } from '../format'

const today = () => new Date().toISOString().slice(0, 10)
const emptyLine = () => ({ account_no: '', amount: '', tax_code: '', description: '' })
// Cuentas que REDUCEN la factura (regla del lado): devoluciones, rappels y pronto pago
const REDUCING = ['606', '608', '609', '706', '708', '709']
const cents = (v) => Math.round((parseFloat(String(v).replace(',', '.')) || 0) * 100)

// Registro de una factura recibida (purchase) o emitida (sale), como el de A3 / Sage / ContaPlus
export default function InvoiceForm({ company, invoiceType, invoices, onPosted }) {
  const { t, language } = useI18n()
  const emptyHeader = () => ({
    document_kind: 'invoice', partner_id: '', external_document_no: '', invoice_date: today(),
    posting_date: '', description: '', corrected_invoice_id: '', corrected_reference: '',
  })
  const [header, setHeader] = useState(emptyHeader())
  const [lines, setLines] = useState([emptyLine()])
  const [partners, setPartners] = useState([])
  const [accounts, setAccounts] = useState([])
  const [taxes, setTaxes] = useState([])
  const [preview, setPreview] = useState(null)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)

  const purchase = invoiceType === 'purchase'

  useEffect(() => {
    const types = purchase ? ['vendor', 'creditor'] : ['customer', 'debtor']
    // Compras: cuentas de gastos (6) e inmovilizado (2) · Ventas: ingresos (7)
    const groups = purchase ? ['6', '2'] : ['7']
    Promise.all([
      supabase.from('v_partners').select('id, name, partner_type, account_no, blocked')
        .eq('company_id', company.id).in('partner_type', types).order('name'),
      supabase.from('gl_accounts').select('id, account_no, name, name_en, template_account')
        .eq('company_id', company.id).eq('account_type', 'posting').order('account_no'),
      supabase.from('v_tax_setup').select('tax_code, tax_type, rate_pct, blocked')
        .eq('company_id', company.id).eq('blocked', false).order('tax_type').order('rate_pct'),
    ]).then(([p, a, x]) => {
      const failed = p.error || a.error || x.error
      if (failed) return setError(failed.message)
      setPartners(p.data.filter((r) => !r.blocked))
      setAccounts(a.data.filter((r) => groups.includes(r.account_no[0])))
      setTaxes(x.data)
    })
    setHeader(emptyHeader()); setLines([emptyLine()]); setPreview(null); setError(''); setMessage('')
  }, [company.id, invoiceType])

  const set = (field) => (e) => { setHeader({ ...header, [field]: e.target.value }); setPreview(null) }
  const setLine = (i, field, value) => {
    setLines((prev) => prev.map((l, j) => (j === i ? { ...l, [field]: value } : l)))
    setPreview(null)
  }
  const byNo = (no) => accounts.find((a) => a.account_no === no.trim())
  const rate = (code) => Number(taxes.find((x) => x.tax_code === code)?.rate_pct ?? 0)
  const credit = header.document_kind === 'credit_memo'
  const reduces = (l) => credit || REDUCING.includes(byNo(l.account_no)?.template_account)

  // Totales orientativos en pantalla (el cálculo oficial lo hace la base de datos)
  const usedLines = lines.filter((l) => l.account_no.trim() && cents(l.amount) > 0)
  const byTax = {}
  for (const l of usedLines) byTax[l.tax_code] = (byTax[l.tax_code] ?? 0) + (reduces(l) ? -1 : 1) * cents(l.amount)
  const base = Object.values(byTax).reduce((s, v) => s + v, 0)
  const tax = Object.entries(byTax).reduce((s, [code, b]) => s + Math.round((b * rate(code)) / 100), 0)

  function payload() {
    return {
      company_id: company.id,
      invoice_type: invoiceType,
      ...header,
      posting_date: header.posting_date || header.invoice_date,
      lines: usedLines.map((l) => ({ ...l, amount: cents(l.amount) / 100 })),
    }
  }

  async function showPreview() {
    setError(''); setMessage('')
    const { data, error } = await supabase.rpc('preview_invoice', { p: payload() })
    if (error) return setError(error.message)
    setPreview(data)
  }

  async function post() {
    setError(''); setMessage(''); setBusy(true)
    const { data, error } = await supabase.rpc('post_invoice', { p: payload() }).single()
    setBusy(false)
    if (error) return setError(error.message)
    setMessage(t('invoicePosted').replace('{no}', data.invoice_no).replace('{entry}', data.entry_no))
    setHeader(emptyHeader()); setLines([emptyLine()]); setPreview(null)
    onPosted?.()
  }

  const partnerInvoices = invoices.filter((i) => i.partner_id === header.partner_id && i.document_kind === 'invoice')
  const listId = `cuentas-factura-${invoiceType}`
  const previewRows = preview?.filter((r) => r.line_role !== 'tax_exempt') ?? []

  return (
    <section className="tarjeta factura">
      <h2>{purchase ? t('newPurchaseInvoice') : t('newSalesInvoice')}</h2>

      <div className="rejilla-cabecera">
        <label>{t('documentKind')}
          <select value={header.document_kind} onChange={set('document_kind')}>
            <option value="invoice">{t('kind.invoice')}</option>
            <option value="credit_memo">{t('kind.credit_memo')}</option>
          </select>
        </label>
        <label>{purchase ? t('vendorOrCreditor') : t('customerOrDebtor')}
          <select value={header.partner_id} onChange={set('partner_id')}>
            <option value="">—</option>
            {partners.map((p) => (
              <option key={p.id} value={p.id}>{p.account_no} · {p.name}</option>
            ))}
          </select>
        </label>
      </div>
      {partners.length === 0 && <p className="aviso">{t('noPartnersForInvoice')}</p>}
      {taxes.length === 0 && <p className="aviso">{t('noTaxesForInvoice')}</p>}

      {credit && (
        <div className="rejilla-cabecera">
          <label>{t('correctedInvoice')}
            <select value={header.corrected_invoice_id} onChange={set('corrected_invoice_id')}>
              <option value="">—</option>
              {partnerInvoices.map((i) => (
                <option key={i.id} value={i.id}>{i.external_document_no ?? i.invoice_no} · {i.invoice_date}</option>
              ))}
            </select>
          </label>
          <label>{t('correctedReference')}
            <input value={header.corrected_reference} onChange={set('corrected_reference')}
                   disabled={Boolean(header.corrected_invoice_id)} />
          </label>
        </div>
      )}

      <div className="rejilla-cabecera">
        {purchase && (
          <label>{t('vendorInvoiceNo')}
            <input value={header.external_document_no} onChange={set('external_document_no')} required />
          </label>
        )}
        <label>{t('invoiceDate')}
          <input type="date" value={header.invoice_date} onChange={set('invoice_date')} />
        </label>
        <label>{t('registrationDate')}
          <input type="date" value={header.posting_date || header.invoice_date} onChange={set('posting_date')} />
        </label>
      </div>
      <input placeholder={t('invoiceDescription')} value={header.description} onChange={set('description')} />

      <p className="ayuda">{purchase ? t('purchaseLinesHelp') : t('salesLinesHelp')}</p>
      <datalist id={listId}>
        {accounts.map((a) => <option key={a.id} value={a.account_no} label={accountName(a, language)} />)}
      </datalist>

      {lines.map((l, i) => {
        const account = byNo(l.account_no)
        return (
          <div key={i} className="linea-factura">
            <div className="cuenta-linea">
              <input list={listId} placeholder={t('baseAccount')} value={l.account_no} autoComplete="off"
                     inputMode="numeric" className={l.account_no.trim() && !account ? 'invalido' : ''}
                     onChange={(e) => setLine(i, 'account_no', e.target.value)} />
              <span className="nombre-cuenta">
                {account ? accountName(account, language) : l.account_no.trim() ? t('accountNotFound') : ''}
                {account && reduces(l) && <strong className="reduce"> · {t('reduces')}</strong>}
              </span>
            </div>
            <input placeholder={t('baseAmount')} inputMode="decimal" value={l.amount}
                   onChange={(e) => setLine(i, 'amount', e.target.value)} />
            <select value={l.tax_code} onChange={(e) => setLine(i, 'tax_code', e.target.value)}>
              <option value="">{t('taxCode')}</option>
              {taxes.map((x) => (
                <option key={x.tax_code} value={x.tax_code}>
                  {t(`taxType.${x.tax_type}`)} {Number(x.rate_pct).toLocaleString(language === 'en' ? 'en-GB' : 'es-ES')} %
                </option>
              ))}
            </select>
            <button type="button" className="secundario" disabled={lines.length === 1} title={t('removeLine')}
                    onClick={() => { setLines(lines.filter((_, j) => j !== i)); setPreview(null) }}>✕</button>
          </div>
        )
      })}
      <button type="button" className="secundario" onClick={() => setLines([...lines, emptyLine()])}>
        + {t('addLine')}
      </button>

      <div className="totales">
        <span>{t('taxBase')}: <strong>{money(base / 100, language)}</strong></span>
        <span>{t('taxAmount')}: <strong>{money(tax / 100, language)}</strong></span>
        <span>{t('invoiceTotal')}: <strong>{money((base + tax) / 100, language)}</strong></span>
      </div>

      <div className="fila">
        <button type="button" className="secundario" onClick={showPreview}>{t('previewEntry')}</button>
        <button type="button" disabled={busy || !preview} onClick={post}>{t('postInvoice')}</button>
      </div>
      {!preview && <p className="ayuda">{t('previewFirst')}</p>}

      {preview && (
        <table className="vista-previa">
          <thead>
            <tr><th>{t('account')}</th><th className="num">{t('debit')}</th><th className="num">{t('credit')}</th></tr>
          </thead>
          <tbody>
            {previewRows.map((r) => (
              <tr key={r.line_no}>
                <td><span className="codigo">{r.account_no}</span> {r.account_name}
                  {r.line_role === 'tax' && <span className="ayuda"> · {t('base')} {money(r.tax_base, language)}</span>}
                </td>
                <td className="num">{Number(r.debit) ? money(r.debit, language) : ''}</td>
                <td className="num">{Number(r.credit) ? money(r.credit, language) : ''}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {error && <p className="aviso">⚠ {error}</p>}
      {message && <p className="exito">✓ {message}</p>}
    </section>
  )
}