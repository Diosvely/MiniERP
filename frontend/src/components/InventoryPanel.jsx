import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { money, shortDate } from '../format'
import { companyPath } from '../router'
import { inventoryLines } from '../adjustments'
import Link from './Link'
import Empty from './Empty'
import Term from './Term'
import ErrorBox from './ErrorBox'

// INVENTARIO DEL CIERRE (v0.37.0, NRV 10.ª): método administrativo. Por cada cuenta de existencias (30-36) se da de
// baja la inicial y de alta la final del recuento (61x / 71x), y se revierte y dota el deterioro (39x). La base de
// datos contabiliza (0047): aquí se escribe el recuento y se ve el asiento antes.
export default function InventoryPanel({ company, readOnly, date }) {
  const { t, language } = useI18n()
  const [rows, setRows] = useState(null)
  const [counts, setCounts] = useState({})
  const [posted, setPosted] = useState(null)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)
  const m = (v) => money(v, language)
  const digits = company.posting_account_digits ?? 8

  async function load() {
    if (!date) return
    const [p, c] = await Promise.all([
      supabase.rpc('inventory_preview', { p_company: company.id, p_date: date }),
      supabase.from('inventory_counts').select('id, count_date, status, entry_id, fiscal_year_id').eq('company_id', company.id)
        .eq('status', 'posted').order('count_date', { ascending: false }),
    ])
    if (p.error || c.error) return setError((p.error || c.error).code === 'PGRST202' ? t('inv.dbMissing') : (p.error || c.error).message)
    setRows(p.data ?? [])
    setPosted((c.data ?? []).find((x) => x.count_date.slice(0, 4) === date.slice(0, 4)) ?? null)
  }
  useEffect(() => { load() }, [company.id, date])   // eslint-disable-line react-hooks/exhaustive-deps

  const set = (no, k, v) => setCounts((c) => ({ ...c, [no]: { ...c[no], [k]: v } }))
  const { lines, variation } = inventoryLines(rows ?? [], counts, digits)
  const lineText = (l) => `${l.account_no} ${l.debit ? t('adj.debitShort') + ' ' + m(l.debit) : t('adj.creditShort') + ' ' + m(l.credit)}`
  const missing = (rows ?? []).some((r) => counts[r.account_no]?.final === undefined || counts[r.account_no]?.final === '')

  async function post() {
    setBusy(true); setError(''); setMessage('')
    const r = await supabase.rpc('post_inventory', { p: { company_id: company.id, count_date: date,
      lines: (rows ?? []).map((x) => ({ account_no: x.account_no, final_value: String(counts[x.account_no]?.final ?? '0').replace(',', '.'),
                                       impairment: String(counts[x.account_no]?.impairment || '0').replace(',', '.') })) } })
    setBusy(false)
    if (r.error) return setError(r.error.message)
    const row = Array.isArray(r.data) ? r.data[0] : r.data
    setMessage(t('inv.posted').replace('{n}', row?.entry_no ?? '').replace('{v}', m(row?.variation)))
    setCounts({}); await load()
  }
  async function undo() {
    setBusy(true); setError(''); setMessage('')
    const r = await supabase.rpc('cancel_inventory', { p_count: posted.id })
    setBusy(false)
    if (r.error) return setError(r.error.message)
    setMessage(t('inv.undone').replace('{n}', r.data)); await load()
  }

  return (
    <section className="tarjeta">
      <h2><Term id="inventoryChange">{t('inv.title')}</Term></h2>
      <p className="ayuda">{t('inv.intro')}</p>
      <ErrorBox error={error} company={company} />
      {message && <p className="exito" role="status">✓ {message}</p>}
      {rows === null ? <p className="ayuda">{t('loadingData')}…</p> : rows.length === 0 ? (
        <Empty icon="📦" text={t('inv.empty')} help={t('inv.emptyHelp')} />
      ) : posted ? (
        <p className="aviso">{t('inv.alreadyPosted').replace('{d}', shortDate(posted.count_date))}{' '}
          <Link to={companyPath(company.id, 'journal')} className="enlace">{t('seeInJournal')} →</Link>
          {!readOnly && <> <button type="button" className="secundario" disabled={busy} onClick={undo}>↶ {t('adj.undo')}</button></>}</p>
      ) : (
        <>
          <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('inv.title')}>
            <table>
              <thead><tr><th scope="col">{t('inv.col.account')}</th><th scope="col" className="num">{t('inv.col.initial')}</th>
                <th scope="col" className="num">{t('inv.col.final')}</th><th scope="col" className="num">{t('inv.col.impairment')}</th>
                <th scope="col" className="num">{t('inv.col.prev')}</th><th scope="col">{t('inv.col.variation')}</th></tr></thead>
              <tbody>{rows.map((r) => (
                <tr key={r.account_no}>
                  <td>{r.account_no} {r.account_name}</td>
                  <td className="num">{m(r.initial_value)}</td>
                  <td className="num">{readOnly ? '—' : <input inputMode="decimal" size={8} aria-label={`${t('inv.col.final')} ${r.account_no}`}
                    value={counts[r.account_no]?.final ?? ''} onChange={(e) => set(r.account_no, 'final', e.target.value)} />}</td>
                  <td className="num">{readOnly ? '—' : <input inputMode="decimal" size={6} placeholder="0" aria-label={`${t('inv.col.impairment')} ${r.account_no}`}
                    value={counts[r.account_no]?.impairment ?? ''} onChange={(e) => set(r.account_no, 'impairment', e.target.value)} />}</td>
                  <td className="num">{m(r.prev_impairment)}</td>
                  <td>{r.variation_account_no}</td>
                </tr>))}</tbody>
            </table>
          </div>
          {!readOnly && !missing && lines.length > 0 && (
            <p className="vista-asiento" role="status">
              <span>{t('adj.previewEntry')} {lines.map(lineText).join(' · ')}</span>
              <span>{t('inv.variation').replace('{v}', m(variation))}</span>
            </p>
          )}
          <p className="ayuda">{t('inv.help')}</p>
          {!readOnly && <button type="button" disabled={busy || missing} onClick={post}>{t('inv.post').replace('{d}', shortDate(date))}</button>}
        </>
      )}
    </section>
  )
}
