import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { fetchAll } from '../paging'
import { useI18n } from '../i18n'
import { money, shortDate } from '../format'
import { workDate } from '../workDate'
import { companyPath } from '../router'
import { ACCRUAL_KINDS, TIERS, accrualAmount, accrualLines, adjustmentTotals, deductibleFrom, defaultSubaccount, globalPreview,
         impairmentAmount, isDeductible, nextDay } from '../adjustments'
import Link from './Link'
import Empty from './Empty'
import ErrorBox from './ErrorBox'

const KINDS = Object.keys(ACCRUAL_KINDS)
const emptyAccrual = () => ({ kind: 'prepaid_expense', description: '', pl_account_no: '', calc: 'period', amount: '',
                              total: '', start: '', months: '12', invoice_id: '' })
const DEFAULT_RATES = { not_due: '0', d1_90: '5', d91_180: '10', d181_365: '25', d365_plus: '50' }

// AJUSTES DE CIERRE (v0.36.0): los ajustes de fin de ejercicio del PGC, cada uno con su asiento (0043).
//   · PERIODIFICACIONES (principio de devengo): gasto o ingreso anticipado (480 / 485) y devengado sin factura
//     (4009 / 4309), contra la propia cuenta de gasto o ingreso; se revierten en el ejercicio siguiente.
//   · DETERIORO DE CLIENTES (NRV 9.ª): individual o global por antigüedad (694 / 490), su reversión (490 / 794) y la
//     insolvencia firme (650 / 430), con los avisos fiscales del Impuesto sobre Sociedades (arts. 13.1 y 104 LIS).
// Como los periodos de diferimiento de Business Central y las correcciones de valor de SAP.
export default function Adjustments({ company, readOnly }) {
  const { t, language } = useI18n()
  const [date, setDate] = useState(() => `${workDate(company).slice(0, 4)}-12-31`)
  const [accruals, setAccruals] = useState([])
  const [impairments, setImpairments] = useState([])
  const [writeoffs, setWriteoffs] = useState([])
  const [accounts, setAccounts] = useState([])
  const [invoices, setInvoices] = useState([])
  const [items, setItems] = useState([])
  const [form, setForm] = useState(emptyAccrual)
  const [revOverride, setRevDate] = useState(null)        // fecha de la reversión (por defecto, el día siguiente al cierre)
  const [action, setAction] = useState(null)              // { kind: 'impair' | 'writeoff', invoice_id, pct }
  const [rates, setRates] = useState(DEFAULT_RATES)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [warnings, setWarnings] = useState([])
  const [busy, setBusy] = useState(false)
  const m = (v) => money(v, language)
  const pct = (v) => Number(v).toLocaleString(language === 'en' ? 'en-GB' : 'es-ES', { maximumFractionDigits: 2 })
  const digits = company.posting_account_digits ?? 8

  async function load() {
    const [a, i, w, g, v] = await Promise.all([
      supabase.from('v_accruals').select('*').eq('company_id', company.id).order('code', { ascending: false }),
      supabase.from('v_receivable_impairments').select('*').eq('company_id', company.id).order('code', { ascending: false }),
      supabase.from('v_receivable_writeoffs').select('*').eq('company_id', company.id).order('writeoff_date', { ascending: false }),
      fetchAll(() => supabase.from('gl_accounts').select('id, account_no, name').eq('company_id', company.id)
        .eq('account_type', 'posting').or('account_no.like.6%,account_no.like.7%').order('account_no')),
      supabase.from('v_invoices').select('id, invoice_type, document_kind, invoice_no, external_document_no, partner_name, invoice_date, total_base')
        .eq('company_id', company.id).eq('document_kind', 'invoice').order('invoice_date', { ascending: false }),
    ])
    const failed = a.error || i.error || w.error || g.error || v.error
    if (failed) return setError(failed.code === 'PGRST205' || failed.code === '42P01' ? t('adj.dbMissing') : failed.message)
    setAccruals(a.data ?? []); setImpairments(i.data ?? []); setWriteoffs(w.data ?? []); setAccounts(g.data ?? []); setInvoices(v.data ?? [])
  }
  useEffect(() => { load() }, [company.id])   // eslint-disable-line react-hooks/exhaustive-deps

  // Facturas emitidas pendientes a la fecha (la antigüedad de saldos, como base del deterioro)
  async function loadItems() {
    if (!date) return
    const { data, error } = await supabase.rpc('open_items', { p_company: company.id, p_date: date })
    if (error) return setError(error.message)
    setItems((data ?? []).filter((x) => x.invoice_type === 'sale' && Number(x.pending) > 0))
  }
  useEffect(() => { loadItems() }, [company.id, date, impairments, writeoffs])   // eslint-disable-line react-hooks/exhaustive-deps
  const revDate = revOverride ?? (date ? nextDay(date) : '')

  async function run(fn, args, ok) {
    setBusy(true); setError(''); setMessage(''); setWarnings([])
    const r = await supabase.rpc(fn, args)
    setBusy(false)
    if (r.error) return setError(r.error.message)
    const row = Array.isArray(r.data) ? r.data[0] : r.data
    setWarnings(row?.warnings ?? [])
    setMessage(ok(row))
    await load()
  }

  // ---------- Periodificaciones ----------
  const k = ACCRUAL_KINDS[form.kind]
  const balanceNo = defaultSubaccount(k.balance, digits)
  const plAccounts = accounts.filter((a) => a.account_no.startsWith(k.group) && !/^6[89]|^79/.test(a.account_no))
  const amount = form.calc === 'period' ? accrualAmount(form.kind, form.total, form.start, form.months, date)
    : Number(String(form.amount).replace(',', '.')) || 0
  const lines = form.pl_account_no ? accrualLines(form.kind, balanceNo, form.pl_account_no, amount) : []
  const invoiceType = k.group === '6' ? 'purchase' : 'sale'
  const kindInvoices = form.kind.startsWith('prepaid') || form.kind.startsWith('deferred')
    ? invoices.filter((i) => i.invoice_type === invoiceType) : []

  function chooseInvoice(id) {
    const inv = invoices.find((i) => i.id === id)
    setForm((f) => ({ ...f, invoice_id: id, ...(inv ? { total: String(inv.total_base ?? ''), start: inv.invoice_date,
      description: f.description || `${inv.partner_name} · ${inv.external_document_no || inv.invoice_no}` } : {}) }))
  }

  const createAccrual = (e) => {
    e.preventDefault()
    run('create_accrual', { p: {
      company_id: company.id, kind: form.kind, description: form.description, pl_account_no: form.pl_account_no, cutoff_date: date,
      ...(form.calc === 'period'
        ? { total_amount: String(form.total).replace(',', '.'), coverage_start: form.start, coverage_months: Number(form.months) }
        : { amount: String(form.amount).replace(',', '.') }),
      invoice_id: form.invoice_id || null } }, (row) => {
      setForm(emptyAccrual())
      return t('adj.accrualCreated').replace('{c}', row?.code ?? '').replace('{n}', row?.entry_no ?? '').replace('{m}', m(row?.amount))
    })
  }
  const pendingAccruals = accruals.filter((a) => a.status === 'active' && a.cutoff_date < revDate)
  const reverseAll = () => run('reverse_accruals', { p_company: company.id, p_date: revDate },
    (n) => t('adj.reversedAll').replace('{n}', n).replace('{d}', shortDate(revDate)))
  const reverseOne = (a) => run('reverse_accrual', { p_accrual: a.id, p_date: nextDay(a.cutoff_date) },
    (n) => t('adj.reversedOne').replace('{c}', a.code).replace('{n}', n))
  const undoAccrual = (a) => run('cancel_accrual', { p_accrual: a.id },
    (n) => t(a.status === 'reversed' ? 'adj.reversalUndone' : 'adj.accrualUndone').replace('{c}', a.code).replace('{n}', n))

  // ---------- Deterioro de clientes ----------
  const active = impairments.filter((i) => i.status === 'active')
  const activeByInvoice = new Map(active.filter((i) => i.method === 'individual').map((i) => [i.invoice_id, i]))
  const activeGlobal = active.find((i) => i.method === 'global')
  const preview = globalPreview(items, new Set(activeByInvoice.keys()), rates)
  const impair = (item) => run('impair_receivable', { p: { invoice_id: item.invoice_id, impair_date: date, pct: String(action.pct).replace(',', '.') } },
    (row) => { setAction(null); return t('adj.impaired').replace('{c}', row?.code ?? '').replace('{n}', row?.entry_no ?? '').replace('{m}', m(row?.amount)) })
  const writeOff = (item) => run('write_off_receivable', { p: { invoice_id: item.invoice_id, writeoff_date: date } },
    (row) => { setAction(null); return t('adj.writtenOff').replace('{n}', row?.entry_no ?? '').replace('{m}', m(row?.amount)).replace('{i}', m(row?.impairment_applied)) })
  const impairGlobal = () => run('impair_receivables_global', { p: { company_id: company.id, impair_date: date,
    rates: Object.fromEntries(TIERS.map((x) => [x, Number(String(rates[x] ?? '0').replace(',', '.')) || 0])) } },
    (row) => t('adj.impaired').replace('{c}', row?.code ?? '').replace('{n}', row?.entry_no ?? '').replace('{m}', m(row?.amount)))
  const reverseImpairment = (i) => run('reverse_impairment', { p_impairment: i.id, p_date: date },
    (n) => t('adj.impairmentReversed').replace('{c}', i.code).replace('{n}', n))
  const undoImpairment = (i) => run('cancel_impairment', { p_impairment: i.id },
    (n) => t(i.status === 'reversed' ? 'adj.reversalUndone' : 'adj.impairmentUndone').replace('{c}', i.code).replace('{n}', n))
  const undoWriteoff = (w) => run('cancel_write_off', { p_writeoff: w.id }, (n) => t('adj.writeoffUndone').replace('{i}', w.invoice_no).replace('{n}', n))

  const tot = adjustmentTotals(accruals, impairments)
  const entryLink = (year, no) => (no ? <Link to={companyPath(company.id, `asiento/${year}/${no}`)} className="num-asiento">{no}</Link> : null)
  const warningText = (w) => t(`adj.warn.${w.code}`).replace('{d}', shortDate(w.deductible_from)).replace('{m}', m(w.erd_limit))
  const lineText = (l) => `${l.account_no} ${l.debit ? t('adj.debitShort') + ' ' + m(l.debit) : t('adj.creditShort') + ' ' + m(l.credit)}`

  return (
    <>
      <section className="tarjeta ajustes">
        <h2>{t('adj.title')}</h2>
        <p className="ayuda">{t('adj.intro')}</p>
        <label className="campo-fecha">{t('adj.date')}
          <input type="date" value={date} onChange={(e) => { setDate(e.target.value); setRevDate(null) }} />
        </label>
        <dl className="cifras-comprobacion">
          <div><dt>{t('adj.pendingAccruals')}</dt><dd>{tot.accruals} · {m(tot.accrualAmount)}</dd></div>
          <div><dt>{t('adj.liveImpairment')}</dt><dd>{m(tot.impairmentAmount)}</dd></div>
        </dl>
        <ErrorBox error={error} company={company} />
        {message && <p className="exito" role="status">✓ {message}</p>}
        {warnings.map((w) => <p key={w.code} className="aviso">⚠ {warningText(w)}</p>)}
      </section>

      {/* ---------------- Periodificaciones ---------------- */}
      <section className="tarjeta">
        <h2>{t('adj.accrualsTitle')}</h2>
        <p className="ayuda">{t('adj.accrualsIntro')}</p>
        {accruals.length === 0 ? <Empty icon="📅" text={t('adj.accrualsEmpty')} help={t('adj.accrualsEmptyHelp')} /> : (
          <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('adj.accrualsTitle')}>
            <table>
              <thead><tr>
                <th scope="col">{t('adj.col.code')}</th><th scope="col">{t('adj.col.concept')}</th><th scope="col">{t('adj.col.accounts')}</th>
                <th scope="col">{t('adj.col.cutoff')}</th><th scope="col" className="num">{t('adj.col.amount')}</th>
                <th scope="col">{t('adj.col.status')}</th>{!readOnly && <th scope="col">{t('adj.col.actions')}</th>}
              </tr></thead>
              <tbody>{accruals.map((a) => (
                <tr key={a.id} className={a.status === 'cancelled' ? 'anulada' : ''}>
                  <td>{a.code}</td>
                  <td>{a.description}<br /><small>{t(`adj.kind.${a.kind}`)}</small></td>
                  <td>{a.balance_account_no} ↔ {a.pl_account_no}</td>
                  <td>{shortDate(a.cutoff_date)} · {t('fa.entry')} {entryLink(a.fiscal_year, a.entry_no)}</td>
                  <td className="num">{m(a.amount)}</td>
                  <td>{a.status === 'reversed'
                    ? <>{t('adj.status.reversed').replace('{d}', shortDate(a.reversal_date))} · {t('fa.entry')} {entryLink(a.reversal_year, a.reversal_entry_no)}</>
                    : t(`adj.status.${a.status}`)}</td>
                  {!readOnly && <td className="acciones">
                    {a.status === 'active' && <button type="button" className="secundario" disabled={busy} onClick={() => reverseOne(a)}>{t('adj.reverse')}</button>}
                    {a.status !== 'cancelled' && <button type="button" className="secundario" disabled={busy} onClick={() => undoAccrual(a)}>↶ {t('adj.undo')}</button>}
                  </td>}
                </tr>))}</tbody>
            </table>
          </div>
        )}
        {!readOnly && pendingAccruals.length > 0 && (
          <div className="fila-amortizar">
            <label>{t('adj.reverseOn')}
              <input type="date" value={revDate} onChange={(e) => setRevDate(e.target.value)} />
            </label>
            <button type="button" disabled={busy || !revDate} onClick={reverseAll}>{t('adj.reverseAll').replace('{n}', pendingAccruals.length)}</button>
          </div>
        )}
      </section>

      {!readOnly && (
        <form className="tarjeta alta-activo" onSubmit={createAccrual}>
          <h2>{t('adj.newAccrual')}</h2>
          <div className="opciones-modo" role="radiogroup" aria-label={t('adj.kindLabel')}>
            {KINDS.map((kind) => (
              <label key={kind} className={form.kind === kind ? 'opcion-modo activa' : 'opcion-modo'}>
                <input type="radio" name="tipo-periodificacion" checked={form.kind === kind}
                       onChange={() => setForm({ ...emptyAccrual(), kind, description: form.description })} />
                <span><strong>{t(`adj.kind.${kind}`)}</strong><small>{t(`adj.kindHelp.${kind}`)}</small></span>
              </label>
            ))}
          </div>
          {kindInvoices.length > 0 && (
            <label>{t('adj.fromInvoice')}
              <select value={form.invoice_id} onChange={(e) => chooseInvoice(e.target.value)}>
                <option value="">—</option>
                {kindInvoices.map((i) => <option key={i.id} value={i.id}>{i.external_document_no || i.invoice_no} · {i.partner_name} · {shortDate(i.invoice_date)} · {m(i.total_base)}</option>)}
              </select>
            </label>
          )}
          <label>{t('adj.description')}<input value={form.description} required onChange={(e) => setForm({ ...form, description: e.target.value })} /></label>
          <label>{t(k.group === '6' ? 'adj.expenseAccount' : 'adj.incomeAccount')}
            <select value={form.pl_account_no} required onChange={(e) => setForm({ ...form, pl_account_no: e.target.value })}>
              <option value="">—</option>
              {plAccounts.map((a) => <option key={a.id} value={a.account_no}>{a.account_no} · {a.name}</option>)}
            </select>
          </label>
          <div className="opciones-modo" role="radiogroup" aria-label={t('adj.calcLabel')}>
            {['period', 'amount'].map((c) => (
              <label key={c} className={form.calc === c ? 'opcion-modo activa' : 'opcion-modo'}>
                <input type="radio" name="calculo" checked={form.calc === c} onChange={() => setForm({ ...form, calc: c })} />
                <span><strong>{t(`adj.calc.${c}`)}</strong><small>{t(`adj.calcHelp.${c}.${form.kind.startsWith('accrued') ? 'accrued' : 'prepaid'}`)}</small></span>
              </label>
            ))}
          </div>
          {form.calc === 'period' ? (
            <div className="rejilla-tres">
              <label>{t('adj.total')}<input inputMode="decimal" required value={form.total} onChange={(e) => setForm({ ...form, total: e.target.value })} /></label>
              <label>{t('adj.start')}<input type="date" required value={form.start} onChange={(e) => setForm({ ...form, start: e.target.value })} /></label>
              <label>{t('adj.months')}<input inputMode="numeric" required value={form.months} onChange={(e) => setForm({ ...form, months: e.target.value.replace(/\D/g, '') })} /></label>
            </div>
          ) : (
            <label>{t('adj.amount')}<input inputMode="decimal" required value={form.amount} onChange={(e) => setForm({ ...form, amount: e.target.value })} /></label>
          )}
          {amount > 0 && (
            <p className="vista-asiento" role="status">
              <span>{t('adj.previewAmount').replace('{m}', m(amount)).replace('{d}', shortDate(date))}</span>
              {lines.length > 0 && <span>{t('adj.previewEntry')} {lines.map(lineText).join(' · ')}</span>}
              {lines.length > 0 && <span>{t('adj.previewReversal').replace('{d}', shortDate(nextDay(date)))}</span>}
            </p>
          )}
          {form.calc === 'period' && form.total && form.start && amount <= 0 && <p className="aviso">⚠ {t('adj.nothingToAccrue')}</p>}
          <button type="submit" disabled={busy || !form.description || !form.pl_account_no || !(amount > 0)}>{t('adj.createAccrual')}</button>
        </form>
      )}

      {/* ---------------- Deterioro de clientes ---------------- */}
      <section className="tarjeta">
        <h2>{t('adj.impairTitle')}</h2>
        <p className="ayuda">{t('adj.impairIntro')}</p>
        {items.length === 0 ? <Empty icon="✅" text={t('adj.noReceivables').replace('{d}', shortDate(date))} /> : (
          <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('adj.impairTitle')}>
            <table>
              <thead><tr>
                <th scope="col">{t('adj.col.invoice')}</th><th scope="col">{t('adj.col.customer')}</th><th scope="col">{t('adj.col.due')}</th>
                <th scope="col" className="num">{t('adj.col.days')}</th><th scope="col" className="num">{t('adj.col.pending')}</th>
                <th scope="col" className="num">{t('adj.col.impaired')}</th>{!readOnly && <th scope="col">{t('adj.col.actions')}</th>}
              </tr></thead>
              <tbody>{items.map((x) => {
                const imp = activeByInvoice.get(x.invoice_id)
                const open = action?.invoice_id === x.invoice_id
                return (
                  <tr key={x.invoice_id} className={open ? 'marcada' : ''}>
                    <td>{x.external_document_no || x.invoice_no}</td>
                    <td>{x.partner_name}</td>
                    <td>{shortDate(x.due_date)}</td>
                    <td className="num">{x.days_overdue}</td>
                    <td className="num">{m(x.pending)}</td>
                    <td className="num">{imp ? <>{m(imp.amount)}<br /><small>{imp.code}</small></> : '—'}</td>
                    {!readOnly && <td className="acciones">
                      {open ? (
                        <div className="accion-deterioro">
                          {action.kind === 'impair' ? (<>
                            <label>{t('adj.pct')}<input inputMode="decimal" value={action.pct} size={4}
                                   onChange={(e) => setAction({ ...action, pct: e.target.value })} /></label>
                            <small>{t('adj.impairPreview').replace('{m}', m(impairmentAmount(x.pending, action.pct)))}</small>
                            <small className={isDeductible(x.due_date, date) ? '' : 'vencida'}>{isDeductible(x.due_date, date)
                              ? t('adj.deductible') : t('adj.warn.not_deductible_6m').replace('{d}', shortDate(deductibleFrom(x.due_date)))}</small>
                            <button type="button" disabled={busy || !(impairmentAmount(x.pending, action.pct) > 0)} onClick={() => impair(x)}>{t('adj.impair')}</button>
                          </>) : (<>
                            <small>{t('adj.writeoffPreview').replace('{m}', m(x.pending)).replace('{i}', imp ? m(imp.amount) : m(0))}</small>
                            <button type="button" disabled={busy} onClick={() => writeOff(x)}>{t('adj.writeoff')}</button>
                          </>)}
                          <button type="button" className="secundario" onClick={() => setAction(null)}>{t('cancel')}</button>
                        </div>
                      ) : imp ? (<>
                        <button type="button" className="secundario" disabled={busy} onClick={() => reverseImpairment(imp)}>{t('adj.reverse')}</button>
                        <button type="button" className="secundario" disabled={busy} onClick={() => setAction({ kind: 'writeoff', invoice_id: x.invoice_id })}>{t('adj.writeoffShort')}</button>
                      </>) : (<>
                        <button type="button" className="secundario" disabled={busy} onClick={() => setAction({ kind: 'impair', invoice_id: x.invoice_id, pct: '100' })}>{t('adj.impairShort')}</button>
                        <button type="button" className="secundario" disabled={busy} onClick={() => setAction({ kind: 'writeoff', invoice_id: x.invoice_id })}>{t('adj.writeoffShort')}</button>
                      </>)}
                    </td>}
                  </tr>)
              })}</tbody>
            </table>
          </div>
        )}

        <h3>{t('adj.globalTitle')}</h3>
        <p className="ayuda">{t('adj.globalIntro')}</p>
        {activeGlobal ? (
          <p className="aviso">{t('adj.globalActive').replace('{c}', activeGlobal.code).replace('{m}', m(activeGlobal.amount))
            .replace('{d}', shortDate(activeGlobal.impair_date))} {t('fa.entry')} {entryLink(activeGlobal.fiscal_year, activeGlobal.entry_no)}
            {!readOnly && <> <button type="button" className="secundario" disabled={busy} onClick={() => reverseImpairment(activeGlobal)}>{t('adj.reverse')}</button>
              <button type="button" className="secundario" disabled={busy} onClick={() => undoImpairment(activeGlobal)}>↶ {t('adj.undo')}</button></>}</p>
        ) : (
          <>
            <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('adj.globalTitle')}>
              <table>
                <thead><tr><th scope="col">{t('adj.col.tier')}</th><th scope="col" className="num">{t('adj.col.pending')}</th>
                  <th scope="col" className="num">%</th><th scope="col" className="num">{t('adj.col.impairment')}</th></tr></thead>
                <tbody>{preview.rows.map((r) => (
                  <tr key={r.tier}><td>{t(`adj.tier.${r.tier}`)}</td><td className="num">{m(r.basis)}</td>
                    <td className="num">{readOnly ? pct(r.pct) : (
                      <input inputMode="decimal" size={4} aria-label={`% ${t(`adj.tier.${r.tier}`)}`} value={rates[r.tier]}
                             onChange={(e) => setRates({ ...rates, [r.tier]: e.target.value })} />)}</td>
                    <td className="num">{m(r.amount)}</td></tr>))}
                  <tr className="total"><td>{t('adj.total')}</td><td className="num">{m(preview.basis)}</td><td /><td className="num"><strong>{m(preview.amount)}</strong></td></tr>
                </tbody>
              </table>
            </div>
            <p className="ayuda">{t('adj.warn.global_not_deductible').replace('{m}', m(preview.erdLimit))}</p>
            {!readOnly && <button type="button" disabled={busy || !(preview.amount > 0)} onClick={impairGlobal}>{t('adj.impairGlobal').replace('{m}', m(preview.amount))}</button>}
          </>
        )}
      </section>

      {(impairments.length > 0 || writeoffs.length > 0) && (
        <section className="tarjeta">
          <h2>{t('adj.historyTitle')}</h2>
          <ul className="lista-activos">
            {impairments.map((i) => (
              <li key={i.id}>
                <strong>{i.code} · {i.method === 'global' ? t('adj.method.global') : `${i.invoice_no} · ${i.partner_name}`}</strong>
                <span>{shortDate(i.impair_date)} · {m(i.amount)} · {t('fa.entry')} {entryLink(i.fiscal_year, i.entry_no)} ·{' '}
                  <span className={`insignia ${i.status === 'active' ? 'abierto' : 'cerrado'}`}>{t(`adj.istatus.${i.status}`)}</span>
                  {i.end_entry_no && <> · {shortDate(i.end_date)} {t('fa.entry')} {entryLink(i.end_year, i.end_entry_no)}</>}</span>
                {!readOnly && i.status === 'reversed' && (
                  <span><button type="button" className="secundario" disabled={busy} onClick={() => undoImpairment(i)}>↶ {t('adj.undo')}</button></span>)}
                {!readOnly && i.status === 'active' && i.method === 'individual' && (
                  <span><button type="button" className="secundario" disabled={busy} onClick={() => undoImpairment(i)}>↶ {t('adj.undo')}</button></span>)}
              </li>
            ))}
            {writeoffs.map((w) => (
              <li key={w.id}>
                <strong>{t('adj.writeoffItem').replace('{i}', w.invoice_no)} · {w.partner_name}</strong>
                <span>{shortDate(w.writeoff_date)} · 650 {m(w.amount)}{Number(w.impairment_applied) > 0 && <> · 490 {m(w.impairment_applied)}</>} · {t('fa.entry')} {entryLink(w.fiscal_year, w.entry_no)}
                  {w.cancelled && <> · <span className="insignia cerrado">{t('adj.status.cancelled')}</span></>}</span>
                {!readOnly && !w.cancelled && <span><button type="button" className="secundario" disabled={busy} onClick={() => undoWriteoff(w)}>↶ {t('adj.undo')}</button></span>}
              </li>
            ))}
          </ul>
        </section>
      )}
    </>
  )
}
