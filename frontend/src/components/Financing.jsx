import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { money, shortDate } from '../format'
import { companyPath } from '../router'
import { workDate } from '../workDate'
import { FREQUENCIES, KINDS, accountKey, balanced, defaultTax, emptyForm, instalmentEntry, paidCount, payload, ready, startEntry, undoable } from '../financing'
import Link from './Link'
import Sources from './Sources'
import ErrorBox from './ErrorBox'

// FINANCIACIÓN (v0.43.0): los préstamos a coste amortizado (NRV 9.ª) y el arrendamiento financiero (NRV 8.ª). La base
// de datos calcula el cuadro con el tipo de interés efectivo y contabiliza (0062 y 0063); aquí se da de alta el
// préstamo o el leasing viendo antes su cuadro y su asiento, se paga cada cuota (la del leasing, como factura de la
// entidad con su IVA / IGIC), se contabiliza el cierre (intereses devengados y reclasificación a corto) y se deshace
// del último movimiento al primero.
// En Business Central no hay módulo estándar de préstamos (se usan asientos periódicos o extensiones); en SAP, Treasury
// and Risk Management (préstamos) y RE-FX / Lease Administration (arrendamientos).
export default function Financing({ company, readOnly }) {
  const { t, language } = useI18n()
  const today = workDate(company)
  const [loans, setLoans] = useState(null)
  const [selected, setSelected] = useState(null)
  const [schedule, setSchedule] = useState([])
  const [events, setEvents] = useState([])
  const [next, setNext] = useState(null)
  const [entryNos, setEntryNos] = useState({})   // id del asiento → [año, nº]
  const [form, setForm] = useState(() => emptyForm('loan', today))
  const [calc, setCalc] = useState(null)
  const [calcError, setCalcError] = useState('')
  const [partners, setPartners] = useState([])
  const [taxes, setTaxes] = useState([])
  const [inv, setInv] = useState({ partner_id: '', doc: '', tax: '', date: '' })
  const [payDate, setPayDate] = useState('')
  const [yeDate, setYeDate] = useState(`${today.slice(0, 4)}-12-31`)
  const [ye, setYe] = useState(null)
  const [confirming, setConfirming] = useState(null)   // 'create' | 'pay' | 'yearEnd' | id del movimiento a deshacer
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [done, setDone] = useState('')
  const [refresh, setRefresh] = useState(0)
  const m = (v) => money(v, language)
  const pct = (v) => `${Number(v ?? 0).toLocaleString(language === 'en' ? 'en-GB' : 'es-ES', { maximumFractionDigits: 4 })} %`
  const canWrite = !readOnly

  // Los préstamos de la empresa, los acreedores (para la factura del leasing) y los tipos de IVA / IGIC
  useEffect(() => {
    let alive = true
    supabase.rpc('loan_status', { p_company: company.id }).then(({ data, error }) => {
      if (!alive) return
      if (error) return setError(error.code === 'PGRST202' ? t('fin.dbMissing') : error.message)
      setLoans(data ?? [])
    })
    return () => { alive = false }
  }, [company.id, refresh])   // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    let alive = true
    Promise.all([
      supabase.from('v_partners').select('id, name, partner_type, blocked').eq('company_id', company.id).order('name'),
      supabase.from('v_tax_setup').select('tax_code, tax_type, rate_pct, rate_category, description, description_en, blocked').eq('company_id', company.id),
    ]).then(([p, x]) => {
      if (!alive) return
      setPartners((p.data ?? []).filter((r) => ['creditor', 'vendor'].includes(r.partner_type) && !r.blocked))
      setTaxes((x.data ?? []).filter((r) => !r.blocked))
    })
    return () => { alive = false }
  }, [company.id])

  // El préstamo elegido: su cuadro, sus movimientos y la cuota siguiente
  useEffect(() => {
    if (!selected) return undefined
    let alive = true
    Promise.all([
      supabase.from('loan_schedule').select('loan_id, n, due_date, payment, interest, reduction, balance').eq('loan_id', selected).order('n'),
      supabase.from('loan_events').select('id, loan_id, seq, kind, event_date, n, amount, entry_id, invoice_id, cancel_invoice_id, status').eq('loan_id', selected).order('seq', { ascending: false }),
      supabase.rpc('loan_next_instalment', { p_loan: selected }),
    ]).then(async ([s, e, x]) => {
      if (!alive) return
      const ev = (e.data ?? []).filter((r) => r.loan_id === selected)
      const ids = ev.map((r) => r.entry_id).filter(Boolean)
      const { data: je } = ids.length ? await supabase.from('journal_entries').select('id, entry_no, posting_date').in('id', ids) : { data: [] }
      if (!alive) return
      setSchedule((s.data ?? []).filter((r) => r.loan_id === selected)); setEvents(ev); setNext(x.error ? null : x.data)
      setEntryNos(Object.fromEntries((je ?? []).map((r) => [r.id, [String(r.posting_date).slice(0, 4), r.entry_no]])))
      setPayDate(x.data?.due_date ?? ''); setInv((v) => ({ ...v, date: x.data?.due_date ?? '' }))
    })
    return () => { alive = false }
  }, [selected, refresh])

  // Cuadro de amortización antes de dar de alta (lo calcula la base de datos: erp.loan_calc)
  useEffect(() => {
    if (!ready(form)) { setCalc(null); setCalcError(''); return undefined }
    let alive = true
    const timer = setTimeout(() => {
      supabase.rpc('loan_calc', { p: payload(form, company.id) }).then(({ data, error }) => {
        if (!alive) return
        setCalc(error ? null : data); setCalcError(error ? error.message : '')
      })
    }, 300)
    return () => { alive = false; clearTimeout(timer) }
  }, [form, company.id])

  // Cierre: intereses devengados y reclasificación a corto de todos los préstamos vivos
  useEffect(() => {
    let alive = true
    supabase.rpc('loan_year_end_preview', { p_company: company.id, p_date: yeDate })
      .then(({ data, error }) => { if (alive) setYe(error ? null : data) })
    return () => { alive = false }
  }, [company.id, yeDate, refresh])

  const loan = (loans ?? []).find((l) => l.loan_id === selected)
  const anyAccrued = (loans ?? []).some((l) => Number(l.accrued) !== 0)
  useEffect(() => { if (!inv.tax && taxes.length) setInv((v) => ({ ...v, tax: defaultTax(taxes) })) }, [taxes, inv.tax])

  async function run(fn, args, ok) {
    setBusy(true); setError(''); setDone('')
    const { data, error } = await supabase.rpc(fn, args)
    setBusy(false); setConfirming(null)
    if (error) return setError(error.message)
    ok?.(data); setRefresh((x) => x + 1)
  }
  const create = () => run('loan_create', { p: payload(form, company.id) }, (d) => {
    setDone(t('fin.created').replace('{c}', d.code).replace('{n}', d.entry_no ?? '').replace('{a}', d.asset_code ? t('fin.createdAsset').replace('{a}', d.asset_code) : ''))
    setSelected(d.loan_id); setForm(emptyForm(form.kind, today))
  })
  const pay = () => run('loan_payment', { p: { loan_id: selected, date: payDate || undefined } },
    (d) => setDone(t('fin.paid').replace('{k}', d.n).replace('{n}', d.entry_no)))
  const invoice = () => run('loan_instalment_invoice', { p: { loan_id: selected, partner_id: inv.partner_id, external_document_no: inv.doc.trim(), tax_code: inv.tax, invoice_date: inv.date || undefined } },
    (d) => { setDone(t('fin.invoiced').replace('{k}', d.n).replace('{i}', d.invoice_no).replace('{n}', d.entry_no)); setInv((v) => ({ ...v, doc: '' })) })
  const undo = () => run('loan_cancel', { p_loan: selected }, (d) => setDone(t('fin.undone').replace('{k}', t(`fin.ev.${d.kind}`)) + (d.credit_memo_no ? ' ' + t('fin.undoneMemo').replace('{i}', d.credit_memo_no) : '')))
  const yearEnd = () => run('loan_year_end', { p_company: company.id, p_date: yeDate }, (d) => setDone(t('fin.yearEndDone').replace('{n}', d.entries)))

  const startLines = startEntry(calc, form.lender_type)
  const taxRate = taxes.find((x) => x.tax_code === inv.tax)?.rate_pct ?? 0
  const nextLines = instalmentEntry(next, taxRate)
  const paid = paidCount(events)
  const lastId = undoable(events)
  const field = (k, label, extra = {}) => (
    <label>{label}
      <input inputMode="decimal" value={form[k] ?? ''} onChange={(e) => setForm({ ...form, [k]: e.target.value })} {...extra} />
    </label>
  )
  const entryTable = (lines, caption) => (
    <div className="tabla-ancha" tabIndex={0} role="region" aria-label={caption}>
      <table className="informe">
        <caption>{caption}</caption>
        <thead><tr><th scope="col">{t('account')}</th><th scope="col" className="num">{t('debit')}</th><th scope="col" className="num">{t('credit')}</th></tr></thead>
        <tbody>{lines.map((l) => (
          <tr key={l.account + l.debit + l.credit}><td><span className="codigo">{l.account}</span> {accountKey(l.account) ? t(`fin.account.${accountKey(l.account)}`) : ''}</td>
            <td className="num">{l.debit ? m(l.debit) : ''}</td><td className="num">{l.credit ? m(l.credit) : ''}</td></tr>))}</tbody>
      </table>
      {!balanced(lines) && <p className="aviso">{t('fin.unbalanced')}</p>}
    </div>
  )
  const entryLink = (id) => {
    const [y, n] = entryNos[id] ?? []
    return n ? <Link className="enlace" to={companyPath(company.id, `asiento/${y}/${n}`)}>{n}</Link> : null
  }
  const confirmBox = (key, text, action, label) => confirming === key && (
    <div className="anular" role="alertdialog" aria-label={text}>
      <p>{text}</p>
      <div className="fila">
        <button type="button" className="secundario" onClick={() => setConfirming(null)}>{t('cancel')}</button>
        <button type="button" disabled={busy} onClick={action}>{label}</button>
      </div>
    </div>
  )

  return (
    <>
      <section className="tarjeta financiacion">
        <div className="titulo-modelo"><h2>{t('fin.title')}</h2><Sources ids={['pgc']} /></div>
        <p className="ayuda">{t('fin.intro')}</p>
        <ErrorBox error={error} company={company} />
        {done && <p className="exito" role="status">✓ {done}</p>}
      </section>

      <section className="tarjeta">
        <h3>{t('fin.listTitle')}</h3>
        {loans && loans.length === 0 && <p className="ayuda">{t('fin.listNone')}</p>}
        {loans && loans.length > 0 && <p className="ayuda">{t('fin.listHelp')}</p>}
        {loans && loans.length > 0 && (
          <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('fin.listTitle')}>
            <table className="informe">
              <thead><tr>
                <th scope="col">{t('fin.col.code')}</th><th scope="col">{t('fin.col.description')}</th><th scope="col" className="num">{t('fin.col.rate')}</th>
                <th scope="col" className="num">{t('fin.col.instalments')}</th><th scope="col" className="num">{t('fin.col.short')}</th><th scope="col" className="num">{t('fin.col.long')}</th>
                {anyAccrued && <th scope="col" className="num">{t('fin.col.accrued')}</th>}<th scope="col">{t('fin.col.next')}</th>
              </tr></thead>
              <tbody>{loans.map((l) => (
                <tr key={l.loan_id} className={l.loan_id === selected ? 'seleccionado' : ''}>
                  <td><button type="button" className="secundario codigo" aria-pressed={l.loan_id === selected} aria-label={`${t(l.loan_id === selected ? 'fin.hide' : 'fin.see')} ${l.code}`}
                    onClick={() => setSelected(l.loan_id === selected ? null : l.loan_id)}>{l.code}</button></td>
                  <td>{l.description}<br /><small className="articulo">{t(`fin.kind.${l.kind}`)}{l.lender ? ` · ${l.lender}` : ''}{l.status === 'repaid' ? ` · ${t('fin.repaid')}` : ''}</small></td>
                  <td className="num">{pct(l.effective_rate_year)}</td>
                  <td className="num">{l.paid} / {l.periods}</td>
                  <td className="num">{m(l.short)}</td><td className="num">{m(l.long)}</td>{anyAccrued && <td className="num">{Number(l.accrued) ? m(l.accrued) : ''}</td>}
                  <td>{l.next ? <>{shortDate(l.next.due_date)}<br /><small className="articulo">{m(l.next.payment)}</small></> : ''}</td>
                </tr>))}</tbody>
            </table>
          </div>
        )}
      </section>

      {loan && (
        <section className="tarjeta">
          <h3>{loan.code} · {loan.description}</h3>
          <p className="ayuda">{t(`fin.detailHelp.${loan.kind}`).replace('{r}', pct(loan.effective_rate_year)).replace('{m}', m(loan.net_amount))}</p>
          <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('fin.scheduleTitle')}>
            <table className="informe">
              <caption>{t('fin.scheduleTitle')}</caption>
              <thead><tr><th scope="col">{t('fin.s.n')}</th><th scope="col">{t('fin.s.due')}</th><th scope="col" className="num">{t('fin.s.payment')}</th>
                <th scope="col" className="num">{t('fin.s.interest')}</th><th scope="col" className="num">{t('fin.s.reduction')}</th><th scope="col" className="num">{t('fin.s.balance')}</th></tr></thead>
              <tbody>{schedule.map((r) => (
                <tr key={r.n} className={r.n <= paid ? 'excluido' : r.n === paid + 1 ? 'seleccionado' : ''}>
                  <td>{r.n}{r.n <= paid && <span className="etiqueta etiqueta-texto"> ✓ {t('fin.s.paid')}</span>}</td><td>{shortDate(r.due_date)}</td>
                  <td className="num">{m(r.payment)}</td><td className="num">{m(r.interest)}</td><td className="num">{m(r.reduction)}</td><td className="num">{m(r.balance)}</td>
                </tr>))}</tbody>
            </table>
          </div>

          {canWrite && next && loan.status === 'active' && (
            <>
              <h4>{t('fin.nextTitle').replace('{k}', next.n).replace('{t}', next.periods)}</h4>
              <p className="ayuda">{t(`fin.nextHelp.${loan.kind}`)}{Number(next.accrued_used) > 0 && ' ' + t('fin.nextAccrued').replace('{m}', m(next.accrued_used))}
                {Number(next.purchase_option) > 0 && ' ' + t('fin.nextOption').replace('{m}', m(next.purchase_option))}</p>
              {loan.kind === 'loan' ? (
                <div className="rejilla-tres">
                  <label>{t('fin.f.payDate')}<input type="date" value={payDate} onChange={(e) => setPayDate(e.target.value)} /></label>
                </div>
              ) : (
                <div className="rejilla-tres">
                  <label>{t('fin.f.lessor')}
                    <select value={inv.partner_id} onChange={(e) => setInv({ ...inv, partner_id: e.target.value })}>
                      <option value="">{t('fin.f.choose')}</option>
                      {partners.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
                    </select>
                  </label>
                  <label>{t('fin.f.invoiceNo')}<input maxLength={40} value={inv.doc} onChange={(e) => setInv({ ...inv, doc: e.target.value })} /></label>
                  <label>{t('fin.f.tax')}
                    <select value={inv.tax} onChange={(e) => setInv({ ...inv, tax: e.target.value })}>
                      {taxes.filter((x) => Number(x.rate_pct) > 0).map((x) => <option key={x.tax_code} value={x.tax_code}>{x.tax_code} · {pct(x.rate_pct)}</option>)}
                    </select>
                  </label>
                  <label>{t('fin.f.invoiceDate')}<input type="date" value={inv.date} onChange={(e) => setInv({ ...inv, date: e.target.value })} /></label>
                </div>
              )}
              {partners.length === 0 && loan.kind === 'leasing' && <p className="aviso-modo">📌 {t('fin.noLessor')} <Link className="enlace" to={companyPath(company.id, 'partners')}>{t('nav.partners.label')} →</Link></p>}
              {entryTable(nextLines, t(`fin.entry.${loan.kind === 'loan' ? 'payment' : 'invoice'}`))}
              {confirming !== 'pay'
                ? <button type="button" disabled={busy || (loan.kind === 'leasing' && (!inv.partner_id || !inv.doc.trim() || !inv.tax))} onClick={() => setConfirming('pay')}>
                  {t(loan.kind === 'loan' ? 'fin.pay' : 'fin.invoice').replace('{k}', next.n)}</button>
                : confirmBox('pay', t(loan.kind === 'loan' ? 'fin.confirmPay' : 'fin.confirmInvoice').replace('{k}', next.n).replace('{m}', m(next.payment)),
                  loan.kind === 'loan' ? pay : invoice, t(loan.kind === 'loan' ? 'fin.pay' : 'fin.invoice').replace('{k}', next.n))}
            </>
          )}

          <h4>{t('fin.eventsTitle')}</h4>
          <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('fin.eventsTitle')}>
            <table className="informe">
              <thead><tr><th scope="col">{t('fin.e.date')}</th><th scope="col">{t('fin.e.kind')}</th><th scope="col" className="num">{t('fin.e.amount')}</th><th scope="col">{t('fin.e.entry')}</th><th scope="col" aria-label={t('fin.undo')} /></tr></thead>
              <tbody>{events.map((e) => (
                <tr key={e.id} className={e.status === 'cancelled' ? 'excluido' : ''}>
                  <td>{shortDate(e.event_date)}</td>
                  <td>{t(`fin.ev.${e.kind}`)}{e.n ? ` ${e.n}` : ''}{e.invoice_id && <small className="articulo"> · {t('fin.e.invoice')}</small>}
                    {e.status === 'cancelled' && <span className="etiqueta etiqueta-texto"> {t('fin.cancelled')}</span>}</td>
                  <td className="num">{m(e.amount)}</td>
                  <td>{e.entry_id ? entryLink(e.entry_id) : ''}</td>
                  <td>
                    {canWrite && e.id === lastId && confirming !== e.id && <button type="button" className="secundario" disabled={busy} onClick={() => setConfirming(e.id)}>↩ {t('fin.undo')}</button>}
                    {confirmBox(e.id, t(e.invoice_id ? 'fin.confirmUndoInvoice' : e.kind === 'start' ? 'fin.confirmUndoStart' : 'fin.confirmUndo').replace('{k}', t(`fin.ev.${e.kind}`)), undo, t('fin.undo'))}
                  </td>
                </tr>))}</tbody>
            </table>
          </div>
          <p className="ayuda">{t('fin.undoHelp')}</p>
        </section>
      )}

      {canWrite && (
        <section className="tarjeta">
          <h3>{t('fin.newTitle')}</h3>
          <div className="rejilla-tres">
            <label>{t('fin.f.kind')}
              <select value={form.kind} onChange={(e) => setForm({ ...emptyForm(e.target.value, form.start_date), description: form.description, lender: form.lender })}>
                {KINDS.map((k) => <option key={k} value={k}>{t(`fin.kind.${k}`)}</option>)}
              </select>
            </label>
            <label>{t('fin.f.description')}<input maxLength={120} value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} placeholder={t(`fin.f.descPh.${form.kind}`)} /></label>
            <label>{t('fin.f.lender')}<input maxLength={80} value={form.lender} onChange={(e) => setForm({ ...form, lender: e.target.value })} /></label>
            {form.kind === 'loan' && (
              <label>{t('fin.f.lenderType')}
                <select value={form.lender_type} onChange={(e) => setForm({ ...form, lender_type: e.target.value })}>
                  {['bank', 'other'].map((k) => <option key={k} value={k}>{t(`fin.lender.${k}`)}</option>)}
                </select>
              </label>
            )}
            <label>{t('fin.f.start')}<input type="date" value={form.start_date} onChange={(e) => setForm({ ...form, start_date: e.target.value })} /></label>
            <label>{t('fin.f.frequency')}
              <select value={form.frequency} onChange={(e) => setForm({ ...form, frequency: e.target.value })}>
                {FREQUENCIES.map((f) => <option key={f} value={f}>{t(`fin.freq.${f}`)}</option>)}
              </select>
            </label>
            {field('periods', t('fin.f.periods'), { inputMode: 'numeric' })}
            {form.kind === 'loan' && <>{field('principal', t('fin.f.principal'))}{field('rate', t('fin.f.rate'))}{field('costs', t('fin.f.costs'))}</>}
            {form.kind === 'leasing' && <>{field('fair_value', t('fin.f.fairValue'))}{field('instalment', t('fin.f.instalment'))}{field('purchase_option', t('fin.f.option'))}
              {field('rate', t('fin.f.contractRate'))}{field('useful_years', t('fin.f.usefulYears'))}</>}
          </div>
          <p className="ayuda">{t(`fin.help.${form.kind}`)}</p>
          {calcError && <ErrorBox error={calcError} company={company} />}

          {calc && (
            <>
              <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('fin.calcTitle')}>
                <table className="casillas">
                  <caption className="oculto">{t('fin.calcTitle')}</caption>
                  <tbody>
                    <tr><td>{t('fin.c.instalment')}</td><td className="num">{m(calc.instalment)}</td></tr>
                    {calc.kind === 'leasing' && <tr><td>{t('fin.c.fairValue')}</td><td className="num">{m(calc.fair_value)}</td></tr>}
                    {calc.kind === 'leasing' && calc.present_value != null && <tr><td>{t('fin.c.presentValue')}</td><td className="num">{m(calc.present_value)}</td></tr>}
                    {Number(calc.costs) > 0 && <tr><td>{t('fin.c.costs')}</td><td className="num">− {m(calc.costs)}</td></tr>}
                    <tr className="total"><td>{t(`fin.c.net.${calc.kind}`)}<small className="articulo"> · {t(calc.kind === 'loan' ? 'fin.c.nrv9' : 'fin.c.nrv8')}</small></td><td className="num">{m(calc.net_amount)}</td></tr>
                    <tr><td>{t('fin.c.rate')}{Number(calc.costs) > 0 && <small className="articulo"> · {t('fin.c.rateCosts').replace('{r}', pct(calc.nominal_rate))}</small>}</td><td className="num">{pct(calc.effective_rate_year)}</td></tr>
                    <tr><td>{t('fin.c.totalInterest')}</td><td className="num">{m(calc.total_interest)}</td></tr>
                    <tr><td>{t('fin.c.firstDue')}</td><td className="num">{shortDate(calc.first_due_date)}</td></tr>
                  </tbody>
                </table>
              </div>
              <details>
                <summary>{t('fin.scheduleSee').replace('{n}', (calc.schedule ?? []).length)}</summary>
                <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('fin.scheduleTitle')}>
                  <table className="informe">
                    <thead><tr><th scope="col">{t('fin.s.n')}</th><th scope="col">{t('fin.s.due')}</th><th scope="col" className="num">{t('fin.s.payment')}</th>
                      <th scope="col" className="num">{t('fin.s.interest')}</th><th scope="col" className="num">{t('fin.s.reduction')}</th><th scope="col" className="num">{t('fin.s.balance')}</th></tr></thead>
                    <tbody>{(calc.schedule ?? []).map((r) => (
                      <tr key={r.n}><td>{r.n}</td><td>{shortDate(r.due_date)}</td><td className="num">{m(r.payment)}</td><td className="num">{m(r.interest)}</td>
                        <td className="num">{m(r.reduction)}</td><td className="num">{m(r.balance)}</td></tr>))}</tbody>
                  </table>
                </div>
              </details>
              {entryTable(startLines, t(`fin.entry.start.${calc.kind}`))}
            </>
          )}
          {confirming !== 'create'
            ? <button type="button" disabled={busy || !calc || !form.description.trim() || (form.kind === 'leasing' && !form.useful_years)} onClick={() => setConfirming('create')}>{t('fin.create')}</button>
            : confirmBox('create', t('fin.confirmCreate').replace('{k}', t(`fin.kind.${form.kind}`)).replace('{d}', shortDate(form.start_date)), create, t('fin.create'))}
        </section>
      )}

      <section className="tarjeta">
        <h3>{t('fin.yearEndTitle')}</h3>
        <p className="ayuda">{t('fin.yearEndHelp')}</p>
        <div className="rejilla-tres">
          <label>{t('fin.f.yearEndDate')}<input type="date" value={yeDate} onChange={(e) => { setConfirming(null); setYeDate(e.target.value) }} /></label>
        </div>
        {ye && ye.loans.length === 0 && <p className="ayuda">{t('fin.yearEndNone')}</p>}
        {ye && ye.loans.length > 0 && (
          <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('fin.yearEndTitle')}>
            <table className="informe">
              <thead><tr><th scope="col">{t('fin.col.code')}</th><th scope="col" className="num">{t('fin.y.accrual')}</th><th scope="col" className="num">{t('fin.y.reclass')}</th><th scope="col">{t('fin.y.note')}</th></tr></thead>
              <tbody>{ye.loans.map((x) => (
                <tr key={x.loan_id}>
                  <td><span className="codigo">{x.code}</span> {x.description}</td>
                  <td className="num">{Number(x.accrual) ? m(x.accrual) : '—'}</td>
                  <td className="num">{Number(x.reclassification) ? m(x.reclassification) : '—'}</td>
                  <td>{x.overdue ? <span className="aviso">⚠ {t('fin.y.overdue').replace('{d}', shortDate(x.overdue_due_date))}</span>
                    : Number(x.accrual) ? t('fin.y.accrualNote').replace('{d}', x.days) : ''}</td>
                </tr>))}
                <tr className="total"><td>{t('fin.y.total')}</td><td className="num">{m(ye.accrual_total)}</td><td className="num">{m(ye.reclassification_total)}</td><td /></tr>
              </tbody>
            </table>
          </div>
        )}
        {canWrite && ye && ye.loans.length > 0 && (confirming !== 'yearEnd'
          ? <button type="button" disabled={busy || ye.overdue > 0 || (Number(ye.accrual_total) === 0 && Number(ye.reclassification_total) === 0)} onClick={() => setConfirming('yearEnd')}>{t('fin.yearEnd')}</button>
          : confirmBox('yearEnd', t('fin.confirmYearEnd').replace('{d}', shortDate(yeDate)), yearEnd, t('fin.yearEnd')))}
        {ye && ye.loans.length > 0 && ye.overdue === 0 && Number(ye.accrual_total) === 0 && Number(ye.reclassification_total) === 0 && <p className="ayuda">✓ {t('fin.yearEndUpToDate')}</p>}
      </section>
    </>
  )
}
