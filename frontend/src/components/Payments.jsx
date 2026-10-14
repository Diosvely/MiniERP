import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { fetchAll } from '../paging'
import { useI18n } from '../i18n'
import { money, shortDate } from '../format'
import { workDate } from '../workDate'
import { companyPath } from '../router'
import { buildApplications, linkCandidates, partnersWithPending, previewEntry } from '../payments'
import Link from './Link'
import Empty from './Empty'
import ErrorBox from './ErrorBox'

// COBROS Y PAGOS (v0.32.0): se paga o se cobra CONTRA EL TERCERO Y SUS FACTURAS, y el ERP hace el asiento.
// Como el diario de pagos de Business Central (tipo de cuenta Proveedor + liquidar) o la compensación de partidas
// abiertas de SAP (F-53 / F-28). Nada de "410 a 572" a mano: la factura sabe si está pagada.
//   · Pestañas: Pagos (facturas recibidas) · Cobros (facturas emitidas)
//   · Registrar: tercero → sus facturas pendientes (la más vencida arriba) → importes → banco o caja → asiento
//   · ¿Ya lo pagaste con un asiento manual? Se VINCULA a sus facturas sin crear otro asiento
//   · Historial con anulación (contraasiento) y enlace a cada asiento
export default function Payments({ company, readOnly }) {
  const { t, language } = useI18n()
  const [type, setType] = useState('payment')                // payment = pagos · collection = cobros
  const invoiceType = type === 'payment' ? 'purchase' : 'sale'
  const [items, setItems] = useState([])                     // partidas abiertas (todas, de los dos tipos)
  const [payments, setPayments] = useState([])
  const [cashAccounts, setCashAccounts] = useState([])
  const [partnerId, setPartnerId] = useState('')
  const [selected, setSelected] = useState({})               // { invoice_id: importe }
  const [form, setForm] = useState({ date: workDate(company), cash: '', description: '' })
  const [linkMode, setLinkMode] = useState(false)
  const [candidates, setCandidates] = useState([])
  const [linkEntry, setLinkEntry] = useState('')
  const [cancelling, setCancelling] = useState(null)         // { id, date, reason }
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)

  async function load() {
    const [o, p, c] = await Promise.all([
      supabase.rpc('open_items', { p_company: company.id }),
      supabase.from('v_payments').select('*').eq('company_id', company.id)
        .order('payment_date', { ascending: false }).order('entry_no', { ascending: false }),
      fetchAll(() => supabase.from('gl_accounts').select('account_no, name, blocked')
        .eq('company_id', company.id).eq('account_type', 'posting').like('account_no', '57%').order('account_no')),
    ])
    const failed = o.error || p.error || c.error
    if (failed) return setError(failed.code === 'PGRST202' ? t('pay.dbMissing') : failed.message)
    setItems(o.data ?? [])
    setPayments(p.data ?? [])
    const cash = (c.data ?? []).filter((a) => !a.blocked && a.account_no.startsWith('57'))
    setCashAccounts(cash)
    setForm((f) => ({ ...f, cash: f.cash || cash.find((a) => a.account_no.startsWith('572'))?.account_no || cash[0]?.account_no || '' }))
  }
  useEffect(() => { load() }, [company.id])   // eslint-disable-line react-hooks/exhaustive-deps

  const partners = partnersWithPending(items, invoiceType)
  const partner = partners.find((p) => p.partner_id === partnerId)
  const partnerItems = items.filter((i) => i.partner_id === partnerId && i.invoice_type === invoiceType && Number(i.pending) > 0)
    .sort((a, b) => (a.due_date < b.due_date ? -1 : a.due_date > b.due_date ? 1 : 0))
  const { apps, total, errors } = buildApplications(selected, partnerItems)
  const m = (v) => money(v, language)
  const list = payments.filter((p) => p.payment_type === type)

  function changeType(ty) {
    setType(ty); setPartnerId(''); setSelected({}); setLinkMode(false); setMessage(''); setError('')
  }
  function choosePartner(id) {
    setPartnerId(id); setSelected({}); setLinkMode(false); setLinkEntry(''); setMessage(''); setError('')
  }
  const toggle = (i) => setSelected((s) => {
    const n = { ...s }
    if (i.invoice_id in n) delete n[i.invoice_id]
    else n[i.invoice_id] = String(i.pending).replace('.', language === 'en' ? '.' : ',')
    return n
  })
  const selectAll = () => setSelected(Object.fromEntries(partnerItems.map((i) => [i.invoice_id, String(i.pending).replace('.', language === 'en' ? '.' : ',')])))

  // Asientos manuales del tercero que se pueden vincular (los que mueven su cuenta en el lado del pago)
  async function openLink() {
    setLinkMode(true); setLinkEntry(''); setError('')
    const { data, error } = await supabase.from('v_general_journal')
      .select('entry_id, fiscal_year, entry_no, posting_date, description, debit, credit, source')
      .eq('company_id', company.id).eq('account_no', partner.account_no).order('posting_date', { ascending: false }).limit(200)
    if (error) return setError(error.message)
    const linked = new Set(payments.filter((p) => p.linked && !p.cancel_entry_no).map((p) => `${p.fiscal_year}/${p.entry_no}`))
    setCandidates(linkCandidates(data ?? [], type, linked))
  }

  async function post() {
    setError(''); setMessage(''); setBusy(true)
    const { data, error } = await supabase.rpc('post_payment', { p: {
      company_id: company.id, payment_type: type, partner_id: partnerId, payment_date: form.date,
      cash_account_no: form.cash, description: form.description || null, applications: apps } }).single()
    setBusy(false)
    if (error) return setError(error.message)
    setMessage(t(type === 'payment' ? 'pay.postedPayment' : 'pay.postedCollection').replace('{n}', data.entry_no).replace('{a}', m(total)))
    setSelected({}); setForm({ ...form, description: '' })
    load()
  }

  async function link() {
    setError(''); setMessage(''); setBusy(true)
    const { error } = await supabase.rpc('link_payment', { p: {
      company_id: company.id, entry_id: linkEntry, partner_id: partnerId, applications: apps } })
    setBusy(false)
    if (error) return setError(error.message)
    const c = candidates.find((x) => x.entry_id === linkEntry)
    setMessage(t('pay.linked').replace('{n}', c?.entry_no ?? '').replace('{a}', m(total)))
    setSelected({}); setLinkMode(false); setLinkEntry('')
    load()
  }

  async function cancel() {
    setError(''); setMessage(''); setBusy(true)
    const { data, error } = await supabase.rpc('cancel_payment', { p_payment: cancelling.id, p_date: cancelling.date || null,
                                                                    p_reason: cancelling.reason || null })
    setBusy(false)
    if (error) return setError(error.message)
    setMessage(data == null ? t('pay.unlinked') : t('pay.cancelled').replace('{n}', data))
    setCancelling(null)
    load()
  }

  const entryLink = (year, no) => <Link to={companyPath(company.id, `asiento/${year}/${no}`)} className="num-asiento">{no}</Link>
  const overdue = (d) => (d > 0 ? <span className="vencida">{t('pay.overdue').replace('{d}', d)}</span> : <span className="ayuda">{t('pay.notDue')}</span>)
  const canPost = apps.length > 0 && errors.length === 0 && total > 0

  return (
    <>
      <nav className="pestanas">
        {['payment', 'collection'].map((ty) => (
          <button key={ty} type="button" className={type === ty ? 'activa' : ''} onClick={() => changeType(ty)}>{t(`pay.tab.${ty}`)}</button>
        ))}
      </nav>

      <section className="tarjeta pagos">
        <h2>{t(type === 'payment' ? 'pay.titlePayment' : 'pay.titleCollection')}</h2>
        <p className="ayuda">{t(type === 'payment' ? 'pay.introPayment' : 'pay.introCollection')}</p>
        <ErrorBox error={error} company={company} />
        {message && <p className="exito">✓ {message}</p>}

        {partners.length === 0 ? (
          <Empty icon="✅" text={t(type === 'payment' ? 'pay.nothingToPay' : 'pay.nothingToCollect')} help={t('pay.emptyHelp')}
                 action={readOnly ? null : t('pay.goInvoices')} to={readOnly ? null : companyPath(company.id, 'invoices')} />
        ) : (
          <label>{t(type === 'payment' ? 'vendorOrCreditor' : 'customerOrDebtor')}
            <select value={partnerId} onChange={(e) => choosePartner(e.target.value)}>
              <option value="">{t('pay.choosePartner').replace('{n}', partners.length)}</option>
              {partners.map((p) => (
                <option key={p.partner_id} value={p.partner_id}>
                  {p.account_no} · {p.name} · {m(p.pending)}{p.maxOverdue > 0 ? ` · ${t('pay.overdue').replace('{d}', p.maxOverdue)}` : ''}
                </option>
              ))}
            </select>
          </label>
        )}

        {partner && (
          <>
            <div className="grafico-cabecera">
              <h3>{t(partnerItems.length === 1 ? 'pay.pendingInvoice' : 'pay.pendingInvoices').replace('{n}', partnerItems.length).replace('{a}', m(partner.pending))}</h3>
              {!readOnly && <button type="button" className="enlace" onClick={selectAll}>{t('pay.selectAll')}</button>}
            </div>
            <ul className="partidas">
              {partnerItems.map((i) => {
                const doc = i.external_document_no ?? i.invoice_no
                const on = i.invoice_id in selected
                return (
                  <li key={i.invoice_id} className={on ? 'marcada' : ''}>
                    {!readOnly && <input type="checkbox" checked={on} onChange={() => toggle(i)} aria-label={`${t('pay.apply')} ${doc}`} />}
                    <div className="partida-info">
                      <strong>{doc}{i.status === 'partial' && <span className="insignia">{t('pay.partial')}</span>}</strong>
                      <span>{i.external_document_no && `${i.invoice_no} · `}{shortDate(i.invoice_date)} · {t('pay.due')} {shortDate(i.due_date)} · {overdue(i.days_overdue)}</span>
                    </div>
                    <span className="partida-pendiente">{m(i.pending)}</span>
                    {!readOnly && on && (
                      <input className="importe" inputMode="decimal" value={selected[i.invoice_id]} aria-label={`${t('pay.amount')} ${doc}`}
                             onChange={(e) => setSelected({ ...selected, [i.invoice_id]: e.target.value })} />
                    )}
                  </li>
                )
              })}
            </ul>
            {errors.map((e) => <p key={e.invoice} className="aviso">⚠ {t(`pay.err.${e.code}`).replace('{i}', e.invoice)}</p>)}

            {!readOnly && !linkMode && (
              <>
                <div className="rejilla-cabecera">
                  <label>{t('date')}<input type="date" value={form.date} onChange={(e) => setForm({ ...form, date: e.target.value })} /></label>
                  <label>{t(type === 'payment' ? 'pay.from' : 'pay.to')}
                    <select value={form.cash} onChange={(e) => setForm({ ...form, cash: e.target.value })}>
                      {cashAccounts.map((a) => <option key={a.account_no} value={a.account_no}>{a.account_no} · {a.name}</option>)}
                    </select>
                  </label>
                </div>
                <input placeholder={t('pay.descriptionOptional')} value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} />
                {cashAccounts.length === 0 && <p className="aviso">⚠ {t('pay.noCash')}</p>}
                {canPost && (
                  <div className="vista-asiento" aria-live="polite">
                    <strong>{t('pay.preview')}</strong>
                    {previewEntry(type, partner.account_no, form.cash, total).map((l) => (
                      <span key={l.account_no}><span className="codigo">{l.account_no}</span> {l.debit ? `${t('debit')} ${m(l.debit)}` : `${t('credit')} ${m(l.credit)}`}</span>
                    ))}
                  </div>
                )}
                <div className="fila-botones">
                  <button type="button" disabled={!canPost || !form.cash || busy} onClick={post}>
                    {t(type === 'payment' ? 'pay.post' : 'pay.postCollection').replace('{a}', m(total))}
                  </button>
                  <button type="button" className="secundario" onClick={openLink}>{t('pay.linkOpen')}</button>
                </div>
              </>
            )}

            {!readOnly && linkMode && (
              <div className="vincular">
                <h3>{t('pay.linkTitle')}</h3>
                <p className="ayuda">{t(type === 'payment' ? 'pay.linkHelpPayment' : 'pay.linkHelpCollection').replace('{c}', partner.account_no)}</p>
                {candidates.length === 0 ? <p>{t('pay.linkNone')}</p> : (
                  <ul className="lista-radio">
                    {candidates.map((c) => (
                      <li key={c.entry_id}>
                        <label className="opcion">
                          <input type="radio" name="vincular" checked={linkEntry === c.entry_id} onChange={() => setLinkEntry(c.entry_id)} />
                          {t('entry')} {c.entry_no} · {shortDate(c.date)} · {c.description} · <strong>{m(c.amount)}</strong>
                          {c.linked && <span className="insignia">{t('pay.alreadyLinked')}</span>}
                        </label>
                      </li>
                    ))}
                  </ul>
                )}
                <div className="fila-botones">
                  <button type="button" disabled={!canPost || !linkEntry || busy} onClick={link}>{t('pay.link').replace('{a}', m(total))}</button>
                  <button type="button" className="secundario" onClick={() => setLinkMode(false)}>{t('cancel')}</button>
                </div>
              </div>
            )}
          </>
        )}
      </section>

      <section className="tarjeta">
        <h2>{t(type === 'payment' ? 'pay.historyPayment' : 'pay.historyCollection')} ({list.length})</h2>
        {list.length === 0 && <p className="ayuda">{t('pay.noHistory')}</p>}
        <ul>
          {list.map((p) => (
            <li key={p.id}>
              <strong>
                {shortDate(p.payment_date)} · {p.partner_name} · {m(p.amount)}
                {p.linked && <span className="insignia">{t('pay.linkedBadge')}</span>}
                {p.cancel_entry_no && <span className="insignia">{t('cancelled')}</span>}
              </strong>
              <span>
                {t('pay.invoices')}: {p.invoices ?? '—'}{p.cash_account_no && ` · ${p.cash_account_no}`}
                {' · '}{t('entry')} {entryLink(p.fiscal_year, p.entry_no)}
                {p.cancel_entry_no && <> · {t('pay.cancelEntry')} {entryLink(p.fiscal_year, p.cancel_entry_no)}</>}
              </span>
              {!readOnly && !p.cancel_entry_no && (cancelling?.id === p.id ? (
                <div className="anular-pago">
                  {!p.linked && (
                    <>
                      <label>{t('date')}<input type="date" value={cancelling.date} onChange={(e) => setCancelling({ ...cancelling, date: e.target.value })} /></label>
                      <input placeholder={t('pay.reason')} value={cancelling.reason} onChange={(e) => setCancelling({ ...cancelling, reason: e.target.value })} />
                    </>
                  )}
                  <p className="ayuda">{t(p.linked ? 'pay.unlinkHelp' : 'pay.cancelHelp')}</p>
                  <div className="fila-botones">
                    <button type="button" className="peligro" disabled={busy} onClick={cancel}>{t(p.linked ? 'pay.unlink' : 'pay.cancel')}</button>
                    <button type="button" className="secundario" onClick={() => setCancelling(null)}>{t('cancel')}</button>
                  </div>
                </div>
              ) : (
                <button type="button" className="enlace pequeno" onClick={() => setCancelling({ id: p.id, date: workDate(company), reason: '' })}>
                  {t(p.linked ? 'pay.unlink' : 'pay.cancel')}
                </button>
              ))}
            </li>
          ))}
        </ul>
      </section>
    </>
  )
}
