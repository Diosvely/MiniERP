import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { fetchAll } from '../paging'
import { useI18n } from '../i18n'
import { money, shortDate } from '../format'
import { companyPath } from '../router'
import { PROVISION_KINDS, defaultSubaccount, excessPrefix, provisionApplicationLines, provisionPrefix, provisionRevisionLines } from '../adjustments'
import Link from './Link'
import Empty from './Empty'
import ErrorBox from './ErrorBox'

const emptyForm = () => ({ kind: 'liabilities', term: 'long', description: '', expense_account_no: '', amount: '' })

// PROVISIONES (v0.37.0, NRV 15.ª): obligaciones presentes de importe o fecha inciertos, con su ficha y sus movimientos
// (dotación, revisión al cierre, reclasificación a corto plazo y aplicación al pagar). La base de datos contabiliza (0045).
export default function ProvisionsPanel({ company, readOnly, date }) {
  const { t, language } = useI18n()
  const [rows, setRows] = useState([])
  const [accounts, setAccounts] = useState([])
  const [form, setForm] = useState(emptyForm)
  const [action, setAction] = useState(null)        // { id, kind: 'revise' | 'apply', amount, cash_account_no }
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)
  const m = (v) => money(v, language)
  const digits = company.posting_account_digits ?? 8

  async function load() {
    const [p, g] = await Promise.all([
      supabase.from('v_provisions').select('*').eq('company_id', company.id).order('code', { ascending: false }),
      fetchAll(() => supabase.from('gl_accounts').select('id, account_no, name').eq('company_id', company.id)
        .eq('account_type', 'posting').or('account_no.like.6%,account_no.like.57%').order('account_no')),
    ])
    const failed = p.error || g.error
    if (failed) return setError(failed.code === 'PGRST205' || failed.code === '42P01' ? t('prv.dbMissing') : failed.message)
    setRows(p.data ?? []); setAccounts(g.data ?? [])
  }
  useEffect(() => { load() }, [company.id])   // eslint-disable-line react-hooks/exhaustive-deps

  async function run(fn, args, ok) {
    setBusy(true); setError(''); setMessage('')
    const r = await supabase.rpc(fn, args)
    setBusy(false)
    if (r.error) return setError(r.error.message)
    const row = Array.isArray(r.data) ? r.data[0] : r.data
    setAction(null)
    setMessage(ok(row))
    await load()
  }

  const expenseAccounts = accounts.filter((a) => a.account_no.startsWith('6') && !/^6[89]/.test(a.account_no))
  const cashAccounts = accounts.filter((a) => a.account_no.startsWith('57'))
  const provNo = defaultSubaccount(provisionPrefix(form.kind, form.term), digits)
  const expNo = form.kind === 'commercial' ? defaultSubaccount('6959', digits) : form.expense_account_no
  const amount = Number(String(form.amount).replace(',', '.')) || 0
  const lineText = (l) => `${l.account_no} ${l.debit ? t('adj.debitShort') + ' ' + m(l.debit) : t('adj.creditShort') + ' ' + m(l.credit)}`
  const entryLink = (year, no) => (no ? <Link to={companyPath(company.id, `asiento/${year}/${no}`)} className="num-asiento">{no}</Link> : null)

  const create = (e) => {
    e.preventDefault()
    run('create_provision', { p: { company_id: company.id, kind: form.kind, term: form.term, description: form.description,
      amount: String(form.amount).replace(',', '.'), provision_date: date, expense_account_no: form.kind === 'commercial' ? null : form.expense_account_no } },
    (row) => { setForm(emptyForm()); return t('prv.created').replace('{c}', row?.code ?? '').replace('{n}', row?.entry_no ?? '') })
  }
  const revise = (p) => run('revise_provision', { p: { provision_id: p.id, review_date: date, new_amount: String(action.amount).replace(',', '.') } },
    (row) => t('prv.revised').replace('{c}', p.code).replace('{n}', row?.entry_no ?? ''))
  const apply = (p) => run('apply_provision', { p: { provision_id: p.id, application_date: date, paid: String(action.amount).replace(',', '.'),
    cash_account_no: action.cash_account_no } }, (row) => t('prv.applied').replace('{c}', p.code).replace('{n}', row?.entry_no ?? ''))
  const reclassify = (p) => run('reclassify_provision', { p_provision: p.id, p_date: date }, (n) => t('prv.reclassified').replace('{c}', p.code).replace('{n}', n))
  const undo = (p) => run('cancel_provision_movement', { p_provision: p.id }, (n) => t('prv.undone').replace('{c}', p.code).replace('{n}', n))

  function preview(p) {
    if (!action || action.id !== p.id) return []
    const a = Number(String(action.amount).replace(',', '.'))
    if (Number.isNaN(a) || String(action.amount).trim() === '') return []
    return action.kind === 'revise'
      ? provisionRevisionLines(p.kind, p.provision_account_no, p.expense_account_no, p.excess_account_no, p.balance, a)
      : provisionApplicationLines(p.provision_account_no, p.expense_account_no, p.excess_account_no, action.cash_account_no || '57…', p.balance, a)
  }

  return (
    <>
      <section className="tarjeta">
        <h2>{t('prv.title')}</h2>
        <p className="ayuda">{t('prv.intro')}</p>
        <ErrorBox error={error} company={company} />
        {message && <p className="exito" role="status">✓ {message}</p>}
        {rows.length === 0 ? <Empty icon="⚖️" text={t('prv.empty')} help={t('prv.emptyHelp')} /> : (
          <ul className="lista-activos">
            {rows.map((p) => {
              const lines = preview(p)
              return (
                <li key={p.id} className={action?.id === p.id ? 'marcada' : ''}>
                  <strong>{p.code} · {p.description}</strong>
                  <span>{t(`prv.kind.${p.kind}`)} · {t(`prv.term.${p.term}`)} · {p.provision_account_no} ·{' '}
                    <span className={`insignia ${p.status === 'active' ? 'abierto' : 'cerrado'}`}>{t(`prv.status.${p.status}`)}</span></span>
                  <span className="importes-activo"><span>{t('prv.balance')} <strong>{m(p.balance)}</strong></span></span>
                  <span className="movimientos-provision">{(p.movements ?? []).map((x) => (
                    <span key={x.seq}>{shortDate(x.date)} · {t(`prv.mov.${x.kind}`)} {m(x.after)}{x.paid != null && <> ({t('prv.paid')} {m(x.paid)})</>} · {t('fa.entry')} {entryLink(x.year, x.entry_no)}</span>
                  ))}</span>
                  {!readOnly && p.status === 'active' && (action?.id === p.id ? (
                    <div className="accion-deterioro">
                      <label>{t(action.kind === 'revise' ? 'prv.newEstimate' : 'prv.paidLabel')}
                        <input inputMode="decimal" value={action.amount} onChange={(e) => setAction({ ...action, amount: e.target.value })} /></label>
                      {action.kind === 'apply' && (
                        <label>{t('prv.cash')}
                          <select value={action.cash_account_no} onChange={(e) => setAction({ ...action, cash_account_no: e.target.value })}>
                            <option value="">—</option>
                            {cashAccounts.map((a) => <option key={a.id} value={a.account_no}>{a.account_no} · {a.name}</option>)}
                          </select></label>)}
                      {lines.length > 0 && <small>{t('adj.previewEntry')} {lines.map(lineText).join(' · ')}</small>}
                      <div className="fila">
                        <button type="button" className="secundario" onClick={() => setAction(null)}>{t('cancel')}</button>
                        <button type="button" disabled={busy || lines.length === 0 || (action.kind === 'apply' && Number(action.amount) > 0 && !action.cash_account_no)}
                                onClick={() => (action.kind === 'revise' ? revise(p) : apply(p))}>{t(`prv.do.${action.kind}`)}</button>
                      </div>
                    </div>
                  ) : (
                    <span className="acciones-provision">
                      <button type="button" className="secundario" disabled={busy} onClick={() => setAction({ id: p.id, kind: 'revise', amount: String(p.balance) })}>{t('prv.revise')}</button>
                      {p.term === 'long' && <button type="button" className="secundario" disabled={busy} onClick={() => reclassify(p)}>{t('prv.reclassify')}</button>}
                      <button type="button" className="secundario" disabled={busy} onClick={() => setAction({ id: p.id, kind: 'apply', amount: String(p.balance), cash_account_no: cashAccounts[0]?.account_no ?? '' })}>{t('prv.apply')}</button>
                      <button type="button" className="secundario" disabled={busy} onClick={() => undo(p)}>↶ {t('adj.undo')}</button>
                    </span>
                  ))}
                  {!readOnly && p.status === 'applied' && (
                    <span><button type="button" className="secundario" disabled={busy} onClick={() => undo(p)}>↶ {t('prv.undoApply')}</button></span>)}
                </li>)
            })}
          </ul>
        )}
      </section>

      {!readOnly && (
        <form className="tarjeta alta-activo" onSubmit={create}>
          <h2>{t('prv.newTitle')}</h2>
          <div className="opciones-modo" role="radiogroup" aria-label={t('prv.kindLabel')}>
            {PROVISION_KINDS.map((k) => (
              <label key={k} className={form.kind === k ? 'opcion-modo activa' : 'opcion-modo'}>
                <input type="radio" name="tipo-provision" checked={form.kind === k} onChange={() => setForm({ ...form, kind: k })} />
                <span><strong>{t(`prv.kind.${k}`)}</strong><small>{t(`prv.kindHelp.${k}`)}</small></span>
              </label>
            ))}
          </div>
          <label>{t('adj.description')}<input value={form.description} required onChange={(e) => setForm({ ...form, description: e.target.value })} /></label>
          <div className="rejilla-tres">
            {form.kind !== 'commercial' && (
              <label>{t('prv.term.label')}
                <select value={form.term} onChange={(e) => setForm({ ...form, term: e.target.value })}>
                  <option value="long">{t('prv.term.long')}</option><option value="short">{t('prv.term.short')}</option>
                </select></label>)}
            {form.kind !== 'commercial' && (
              <label>{t('prv.expense')}
                <select value={form.expense_account_no} required onChange={(e) => setForm({ ...form, expense_account_no: e.target.value })}>
                  <option value="">—</option>
                  {expenseAccounts.map((a) => <option key={a.id} value={a.account_no}>{a.account_no} · {a.name}</option>)}
                </select></label>)}
            <label>{t('adj.amount')}<input inputMode="decimal" required value={form.amount} onChange={(e) => setForm({ ...form, amount: e.target.value })} /></label>
          </div>
          {amount > 0 && expNo && (
            <p className="vista-asiento" role="status">
              <span>{t('adj.previewEntry')} {expNo} {t('adj.debitShort')} {m(amount)} · {provNo} {t('adj.creditShort')} {m(amount)}</span>
              <span>{t('prv.excessNote').replace('{a}', defaultSubaccount(excessPrefix(form.kind), digits))}</span>
            </p>
          )}
          <p className="ayuda">{t('prv.newHelp')}</p>
          <button type="submit" disabled={busy || !form.description || !(amount > 0) || !expNo}>{t('prv.create')}</button>
        </form>
      )}
    </>
  )
}
