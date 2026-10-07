import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { accountName, money, taxLabel } from '../format'

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
    posting_date: '', description: '', corrected_invoice_id: '', corrected_reference: '', withholding_code: '',
  })
  const [header, setHeader] = useState(emptyHeader())
  const [lines, setLines] = useState([emptyLine()])
  const [partners, setPartners] = useState([])
  const [accounts, setAccounts] = useState([])
  const [taxes, setTaxes] = useState([])
  const [withholdings, setWithholdings] = useState([])
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
      supabase.from('v_partners').select('id, name, partner_type, account_no, blocked, tax_territory, equivalence_surcharge')
        .eq('company_id', company.id).in('partner_type', types).order('name'),
      supabase.from('gl_accounts').select('id, account_no, name, name_en, template_account')
        .eq('company_id', company.id).eq('account_type', 'posting').order('account_no'),
      supabase.from('v_tax_setup').select('tax_code, tax_type, rate_pct, rate_category, equivalence_surcharge_pct, description, description_en, blocked')
        .eq('company_id', company.id).eq('blocked', false).order('tax_type').order('rate_pct', { ascending: false }),
      supabase.from('tax_codes').select('code, exemption_key'),
      supabase.from('v_withholding_setup').select('withholding_code, rate_pct, description, description_en, blocked')
        .eq('company_id', company.id).eq('blocked', false).order('rate_pct'),
    ]).then(([p, a, x, k, w]) => {
      const failed = p.error || a.error || x.error || k.error || w.error
      if (failed) return setError(failed.message)
      setPartners(p.data.filter((r) => !r.blocked))
      setAccounts(a.data.filter((r) => groups.includes(r.account_no[0])))
      // Primero los tipos con cuota (de mayor a menor) y después las operaciones sin cuota con su causa
      const keys = Object.fromEntries(k.data.map((c) => [c.code, c.exemption_key]))
      setTaxes(x.data.map((r) => ({ ...r, exemption_key: keys[r.tax_code] })))
      setWithholdings(w.data)
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
  // En ISP / adquisición intracomunitaria la cuota la declara la empresa (no la cobra el proveedor): no suma al total
  const selfAssessedCode = (code) => ['reverse_charge', 'intra_eu_acquisition'].includes(taxes.find((x) => x.tax_code === code)?.rate_category)
  const tax = Object.entries(byTax).filter(([code]) => !selfAssessedCode(code))
    .reduce((s, [code, b]) => s + Math.round((b * rate(code)) / 100), 0)
  const selfAssessed = Object.entries(byTax).filter(([code]) => selfAssessedCode(code))
    .reduce((s, [code, b]) => s + Math.round((b * rate(code)) / 100), 0)
  // Retención IRPF sobre la base (sin el impuesto): se resta de lo que se paga o se cobra
  const whRate = Number(withholdings.find((w) => w.withholding_code === header.withholding_code)?.rate_pct ?? 0)
  const withheld = Math.round((base * whRate) / 100)
  const partner = partners.find((p) => p.id === header.partner_id)
  // Recargo de equivalencia: venta a un cliente en recargo, o compra de una empresa en recargo
  const companyRE = company.vat_regime === 'equivalence_surcharge'
  const addsSurcharge = (!purchase && partner?.equivalence_surcharge) || (purchase && companyRE)
  const surcharge = addsSurcharge ? Object.entries(byTax).reduce((s, [code, b]) =>
    s + Math.round((b * Number(taxes.find((x) => x.tax_code === code)?.equivalence_surcharge_pct ?? 0)) / 100), 0) : 0
  const total = base + tax + surcharge
  const foreignPartner = partner && partner.tax_territory !== company.tax_territory
  const taxOf = (code) => taxes.find((x) => x.tax_code === code)
  const descr = (x) => (language === 'en' ? x.description_en || x.description : x.description)

  function payload() {
    return {
      company_id: company.id,
      invoice_type: invoiceType,
      ...header,
      withholding_code: header.withholding_code || null,
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
      {!purchase && partner?.equivalence_surcharge && <p className="ayuda">➕ {t('reCustomerHint')}</p>}
      {purchase && companyRE && <p className="ayuda">➕ {t('reCompanyHint')}</p>}
      {foreignPartner && <p className="ayuda">🌍 {t('foreignPartnerHint').replace('{t}', t(`territory.${partner.tax_territory}`))}</p>}
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
      {withholdings.length > 0 && (
        <label className="retencion">{t('withholding')}
          <select value={header.withholding_code} onChange={set('withholding_code')}>
            <option value="">{t('noWithholding')}</option>
            {withholdings.map((w) => (
              <option key={w.withholding_code} value={w.withholding_code}>
                IRPF {Number(w.rate_pct).toLocaleString(language === 'en' ? 'en-GB' : 'es-ES')} % · {descr(w)}
              </option>
            ))}
          </select>
        </label>
      )}

      <p className="ayuda">{purchase ? t('purchaseLinesHelp') : t('salesLinesHelp')}</p>
      <datalist id={listId}>
        {accounts.map((a) => <option key={a.id} value={a.account_no} label={accountName(a, language)} />)}
      </datalist>

      {lines.map((l, i) => {
        const account = byNo(l.account_no)
        const lineTax = taxOf(l.tax_code)
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
                <option key={x.tax_code} value={x.tax_code}>{taxLabel(x, t, language)}</option>
              ))}
            </select>
            <button type="button" className="secundario" disabled={lines.length === 1} title={t('removeLine')}
                    onClick={() => { setLines(lines.filter((_, j) => j !== i)); setPreview(null) }}>✕</button>
            {lineTax?.exemption_key && <span className="causa-exencion">{descr(lineTax)}</span>}
          </div>
        )
      })}
      <button type="button" className="secundario" onClick={() => setLines([...lines, emptyLine()])}>
        + {t('addLine')}
      </button>

      <div className="totales">
        <span>{t('taxBase')}: <strong>{money(base / 100, language)}</strong></span>
        <span>{t('taxAmount')}: <strong>{money(tax / 100, language)}</strong></span>
        {surcharge > 0 && <span>{t('equivalenceSurcharge')}: <strong>{money(surcharge / 100, language)}</strong></span>}
        <span>{t('invoiceTotal')}: <strong>{money(total / 100, language)}</strong></span>
        {whRate > 0 && <span>{t('withholding')}: <strong>− {money(withheld / 100, language)}</strong></span>}
        {whRate > 0 && (
          <span>{purchase ? t('amountToPay') : t('amountToCollect')}: <strong>{money((total - withheld) / 100, language)}</strong></span>
        )}
        {selfAssessed !== 0 && <span>{t('selfAssessed')}: <strong>{money(selfAssessed / 100, language)}</strong></span>}
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
                  {r.line_role !== 'base' && r.line_role !== 'partner' && (
                    <span className="ayuda"> · {t(`previewRole.${r.line_role}`)} · {t('base')} {money(r.tax_base, language)}</span>
                  )}
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
