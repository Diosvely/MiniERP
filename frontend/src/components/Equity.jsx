import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { money, shortDate } from '../format'
import { companyPath } from '../router'
import { workDate } from '../workDate'
import { KINDS, PREVIEW_RPC, RPC, STATUS_ROWS, balanced, emptyForm, payload, previewEntries, undoable } from '../equity'
import Link from './Link'
import Sources from './Sources'
import ErrorBox from './ErrorBox'

// OPERACIONES SOCIETARIAS (v0.42.0): el patrimonio neto de una sociedad y lo que la junta o el órgano de
// administración acuerdan sobre él — constitución, ampliaciones, dividendos pasivos, reparto del resultado, dividendos
// a cuenta y su pago, y pérdidas. La base de datos comprueba la LSC y contabiliza (0060 y 0061); aquí se elige la
// operación, se ve el asiento antes y se contabiliza o se deshace (de la última a la primera).
// En BC y SAP no hay pantalla equivalente: estas operaciones se registran con asientos manuales en el diario general.
export default function Equity({ company, readOnly }) {
  const { t, language } = useI18n()
  const [date, setDate] = useState(() => workDate(company))
  const [status, setStatus] = useState(null)
  const [ops, setOps] = useState([])
  const [entryNos, setEntryNos] = useState({})   // id del asiento → [año, nº]
  const [kind, setKind] = useState('distribution')
  const [form, setForm] = useState(() => emptyForm('distribution', 'sl'))
  const [prev, setPrev] = useState(null)         // vista previa del reparto o del dividendo a cuenta (la base de datos)
  const [confirming, setConfirming] = useState(null)   // 'post' | id de la operación a deshacer
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [done, setDone] = useState(null)         // última operación contabilizada: { code, entry_nos }
  const [refresh, setRefresh] = useState(0)
  const m = (v) => money(v, language)
  const canWrite = !readOnly

  // Estado del patrimonio neto a la fecha e historial de operaciones
  useEffect(() => {
    let alive = true
    Promise.all([
      supabase.rpc('equity_status', { p_company: company.id, p_date: date }),
      supabase.from('equity_operations').select('id, code, kind, op_date, description, status, entry_ids, result').eq('company_id', company.id).order('code', { ascending: false }),
    ]).then(async ([s, o]) => {
      if (!alive) return
      if (s.error) return setError(s.error.code === 'PGRST202' ? t('eq.dbMissing') : s.error.message)
      const list = o.data ?? []
      const ids = list.flatMap((x) => x.entry_ids ?? [])
      const { data: e } = ids.length
        ? await supabase.from('journal_entries').select('id, entry_no, posting_date').in('id', ids)
        : { data: [] }
      if (!alive) return
      setStatus(s.data); setOps(list)
      setEntryNos(Object.fromEntries((e ?? []).map((x) => [x.id, [String(x.posting_date).slice(0, 4), x.entry_no]])))
    })
    return () => { alive = false }
  }, [company.id, date, refresh])   // eslint-disable-line react-hooks/exhaustive-deps

  // Vista previa del reparto o del dividendo a cuenta (la calcula la base de datos con la LSC)
  useEffect(() => {
    if (!PREVIEW_RPC[kind]) return undefined
    let alive = true
    supabase.rpc(PREVIEW_RPC[kind], { p: payload(kind, form, company.id, date) })
      .then(({ data, error }) => { if (alive) setPrev(error ? null : data) })
    return () => { alive = false }
  }, [kind, form, date, company.id, refresh])

  function choose(k) {
    setKind(k); setForm(emptyForm(k, status?.legal_form)); setPrev(null); setConfirming(null); setDone(null); setError('')
  }

  async function post() {
    setBusy(true); setError('')
    const { data, error } = await supabase.rpc(RPC[kind], { p: payload(kind, form, company.id, date) })
    setBusy(false); setConfirming(null)
    if (error) return setError(error.message)
    setDone(data); setForm(emptyForm(kind, status?.legal_form)); setRefresh((x) => x + 1)
  }
  async function undo(id) {
    setBusy(true); setError('')
    const { error } = await supabase.rpc('equity_cancel', { p_operation: id })
    setBusy(false); setConfirming(null)
    if (error) return setError(error.message)
    setDone(null); setRefresh((x) => x + 1)
  }
  async function setLegalForm(f) {
    setError('')
    const { error } = await supabase.rpc('set_legal_form', { p_company: company.id, p_form: f })
    if (error) return setError(error.message)
    setRefresh((x) => x + 1)
  }

  const entries = previewEntries(kind, form, status ?? {}, prev)
  const warnings = PREVIEW_RPC[kind] ? prev?.warnings ?? [] : []
  const blocked = PREVIEW_RPC[kind] ? !prev?.ok : entries.length === 0
  const lastId = undoable(ops)
  const isAdmin = company.my_role === 'admin'
  const field = (k, label, extra = {}) => (
    <label>{label}
      <input inputMode="decimal" value={form[k] ?? ''} onChange={(e) => setForm({ ...form, [k]: e.target.value })} {...extra} />
    </label>
  )
  const warnText = (w) => t(`eq.warn.${w.code}`).replace('{m}', m(w.min ?? w.interim ?? w.available ?? w.left ?? w.max ?? w.cash ?? w.net_worth_after ?? 0))
    .replace('{c}', m(w.capital ?? 0))
  const entryLink = (id) => {
    const [y, n] = entryNos[id] ?? []
    return n ? <Link key={id} className="enlace" to={companyPath(company.id, `asiento/${y}/${n}`)}>{n}</Link> : null
  }

  return (
    <>
      <section className="tarjeta operaciones-societarias">
        <div className="titulo-modelo"><h2>{t('eq.title')}</h2><Sources ids={['lsc', 'pgc']} /></div>
        <p className="ayuda">{t('eq.intro')}</p>
        <div className="rejilla-tres">
          <label>{t('eq.date')}
            <input type="date" value={date} onChange={(e) => { setConfirming(null); setDate(e.target.value) }} />
          </label>
          <label>{t('eq.legalForm')}
            <select value={status?.legal_form ?? 'sl'} disabled={!canWrite || !isAdmin || ops.some((o) => o.status === 'posted')}
                    onChange={(e) => setLegalForm(e.target.value)}>
              {['sl', 'sa'].map((f) => <option key={f} value={f}>{t(`eq.form.${f}`)}</option>)}
            </select>
          </label>
        </div>
        <p className="ayuda">{t(ops.some((o) => o.status === 'posted') ? 'eq.legalFormLocked' : 'eq.legalFormHelp')}</p>
        <ErrorBox error={error} company={company} />
      </section>

      {status && (
        <section className="tarjeta">
          <h3>{t('eq.statusTitle').replace('{d}', shortDate(date))}</h3>
          <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('eq.statusTitle').replace('{d}', '')}>
            <table className="casillas">
              <tbody>
                {STATUS_ROWS.filter(([k]) => Number(status[k]) !== 0 || ['capital', 'legal_reserve'].includes(k)).map(([k, s]) => (
                  <tr key={k}><td>{t(`eq.st.${k}`)}</td><td className="num">{s < 0 && Number(status[k]) ? '−' : ''}{m(status[k])}</td></tr>))}
                <tr className="total"><td>{t('eq.st.net_worth')}</td><td className="num">{m(status.net_worth)}</td></tr>
              </tbody>
            </table>
          </div>
          <p className="ayuda">
            {t(status.low_capital_sl ? 'eq.reserveCapLow' : 'eq.reserveCap').replace('{m}', m(status.legal_reserve_cap))}
            {Number(status.dividend_payable) > 0 && <> · {t('eq.st.dividend_payable')}: <strong>{m(status.dividend_payable)}</strong></>}
            {Number(status.called_unpaid) > 0 && <> · {t('eq.st.called_unpaid')}: <strong>{m(status.called_unpaid)}</strong></>}
          </p>
          {Number(status.result_to_distribute) !== 0 && (
            <p className="aviso-modo">📌 {t('eq.pending').replace('{m}', m(status.result_to_distribute))}{' '}
              {kind !== 'distribution' && <button type="button" className="enlace" onClick={() => choose('distribution')}>{t('eq.kind.distribution')} →</button>}</p>
          )}
        </section>
      )}

      {canWrite && status && (
        <section className="tarjeta">
          <h3>{t('eq.newTitle')}</h3>
          <label>{t('eq.kindLabel')}
            <select value={kind} onChange={(e) => choose(e.target.value)}>
              {KINDS.map((k) => <option key={k} value={k}>{t(`eq.kind.${k}`)}</option>)}
            </select>
          </label>
          <p className="ayuda">{t(`eq.help.${kind}`)}</p>

          <div className="rejilla-tres">
            {kind === 'incorporation' && <>{field('capital', t('eq.f.capital'))}{field('paid_pct', t('eq.f.paid_pct'), { disabled: status.legal_form === 'sl' })}</>}
            {kind === 'capital_increase' && <>{field('nominal', t('eq.f.nominal'))}{field('premium', t('eq.f.premium'))}{field('paid_pct', t('eq.f.paid_pct'), { disabled: status.legal_form === 'sl' })}</>}
            {kind === 'reserves_to_capital' && <>{field('amount', t('eq.f.amount'))}
              <label>{t('eq.f.source')}
                <select value={form.source} onChange={(e) => setForm({ ...form, source: e.target.value })}>
                  <option value="113">113 · {t('eq.account.113')}</option><option value="110">110 · {t('eq.account.110')}</option>
                </select>
              </label></>}
            {kind === 'call' && <>{field('amount', t('eq.f.amount'))}
              <label className="opcion"><input type="checkbox" checked={form.paid} onChange={(e) => setForm({ ...form, paid: e.target.checked })} /> {t('eq.f.paid')}</label></>}
            {kind === 'distribution' && <>{field('dividend', t('eq.f.dividend'), { placeholder: m(status.interim_dividend) })}
              {field('legal_reserve', t('eq.f.legal_reserve'), { placeholder: prev?.legal_reserve_min != null ? m(prev.legal_reserve_min) : '' })}</>}
            {kind === 'interim_dividend' && <>{field('amount', t('eq.f.amount'))}{field('estimated_tax', t('eq.f.estimated_tax'), { placeholder: prev ? m(prev.estimated_tax) : '' })}</>}
            {kind === 'dividend_payment' && <>{field('amount', t('eq.f.amount'), { placeholder: m(status.dividend_payable) })}
              <label className="opcion"><input type="checkbox" checked={form.withholding} onChange={(e) => setForm({ ...form, withholding: e.target.checked })} /> {t('eq.f.withholding')}</label>
              {!form.withholding && <label>{t('eq.f.no_withholding_reason')}
                <input maxLength={200} value={form.no_withholding_reason} placeholder={t('eq.f.reasonPlaceholder')} onChange={(e) => setForm({ ...form, no_withholding_reason: e.target.value })} /></label>}</>}
            {(kind === 'loss_offset' || kind === 'capital_reduction') && field('amount', t('eq.f.amount'))}
          </div>

          {kind === 'distribution' && prev && Number(prev.result) !== 0 && (
            <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('eq.distTitle')}>
              <table className="casillas">
                <caption className="oculto">{t('eq.distTitle')}</caption>
                <tbody>
                  <tr><td>{t('eq.d.result')}</td><td className="num">{m(prev.result)}</td></tr>
                  {Number(prev.offset_losses) > 0 && <tr><td>{t('eq.d.offset')}</td><td className="num">− {m(prev.offset_losses)}</td></tr>}
                  {prev.result > 0 && <tr><td>{t('eq.d.legal')}<small className="articulo"> · {t(prev.low_capital_sl ? 'eq.d.legalRuleLow' : 'eq.d.legalRule')}</small></td><td className="num">− {m(prev.legal_reserve)}</td></tr>}
                  {prev.result > 0 && <tr className="total"><td>{t('eq.d.available')}</td><td className="num">{m(prev.available)}</td></tr>}
                  {prev.result > 0 && <tr><td>{t('eq.d.dividend')}{Number(prev.interim) > 0 && <small className="articulo"> · {t('eq.d.interimPart').replace('{m}', m(prev.interim))}</small>}</td><td className="num">− {m(prev.dividend)}</td></tr>}
                  {prev.result > 0 && <tr className="total"><td>{t('eq.d.voluntary')}</td><td className="num">{m(prev.voluntary)}</td></tr>}
                  <tr><td>{t('eq.d.netWorth')}<small className="articulo"> · LSC art. 273</small></td><td className="num">{m(prev.net_worth_after)} {prev.result > 0 && Number(prev.dividend) > 0 && (prev.net_worth_after >= prev.capital ? '≥' : '<')} {prev.result > 0 && Number(prev.dividend) > 0 && m(prev.capital)}</td></tr>
                </tbody>
              </table>
            </div>
          )}
          {kind === 'interim_dividend' && prev && (
            <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('eq.intTitle')}>
              <table className="casillas">
                <caption className="oculto">{t('eq.intTitle')}</caption>
                <tbody>
                  <tr><td>{t('eq.i.result')}</td><td className="num">{m(prev.result_since_close)}</td></tr>
                  {Number(prev.prior_losses) > 0 && <tr><td>{t('eq.i.losses')}</td><td className="num">− {m(prev.prior_losses)}</td></tr>}
                  <tr><td>{t('eq.i.tax')}</td><td className="num">− {m(prev.estimated_tax)}</td></tr>
                  <tr><td>{t('eq.i.legal')}</td><td className="num">− {m(prev.legal_reserve)}</td></tr>
                  {Number(prev.already_paid) > 0 && <tr><td>{t('eq.i.paid')}</td><td className="num">− {m(prev.already_paid)}</td></tr>}
                  <tr className="total"><td>{t('eq.i.max')}<small className="articulo"> · LSC art. 277</small></td><td className="num">{m(prev.max)}</td></tr>
                  <tr><td>{t('eq.i.cash')}</td><td className="num">{m(prev.cash)}</td></tr>
                </tbody>
              </table>
            </div>
          )}
          {warnings.length > 0 && (
            <ul className="comprobaciones">
              {warnings.map((w, i) => <li key={i} className={w.code === 'losses_left' ? 'info' : 'warning'}><span className="icono">{w.code === 'losses_left' ? 'ℹ' : '⚠'}</span> {warnText(w)}</li>)}
            </ul>
          )}

          {entries.length > 0 && (
            <>
              <h4>{t('eq.entriesPreview')}</h4>
              {entries.map((e) => (
                <div key={e.key} className="tabla-ancha" tabIndex={0} role="region" aria-label={t(`eq.entry.${e.key}`)}>
                  <table className="informe">
                    <caption>{t(`eq.entry.${e.key}`)}</caption>
                    <thead><tr><th scope="col">{t('account')}</th><th scope="col" className="num">{t('debit')}</th><th scope="col" className="num">{t('credit')}</th></tr></thead>
                    <tbody>{e.lines.map((l) => (
                      <tr key={l.account + l.debit}><td><span className="codigo">{l.account}</span> {t(`eq.account.${l.account}`)}</td>
                        <td className="num">{l.debit ? m(l.debit) : ''}</td><td className="num">{l.credit ? m(l.credit) : ''}</td></tr>))}</tbody>
                  </table>
                </div>
              ))}
              {!balanced(entries) && <p className="aviso">{t('eq.unbalanced')}</p>}
            </>
          )}

          {confirming !== 'post'
            ? <button type="button" disabled={busy || blocked} onClick={() => setConfirming('post')}>{t('eq.post')}</button>
            : (
              <div className="anular" role="alertdialog" aria-label={t('eq.confirmPost')}>
                <p>{t('eq.confirmPost').replace('{k}', t(`eq.kind.${kind}`)).replace('{d}', shortDate(date))}</p>
                <div className="fila">
                  <button type="button" className="secundario" onClick={() => setConfirming(null)}>{t('cancel')}</button>
                  <button type="button" disabled={busy} onClick={post}>{t('eq.post')}</button>
                </div>
              </div>
            )}
          {done && <p className="exito" role="status">✓ {t('eq.posted').replace('{c}', done.code).replace('{n}', (done.entry_nos ?? []).join(', '))}</p>}
        </section>
      )}

      <section className="tarjeta">
        <h3>{t('eq.historyTitle')}</h3>
        {ops.length === 0 ? <p className="ayuda">{t('eq.historyNone')}</p> : (
          <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('eq.historyTitle')}>
            <table className="informe">
              <thead><tr><th scope="col">{t('eq.col.code')}</th><th scope="col">{t('eq.col.date')}</th><th scope="col">{t('eq.col.kind')}</th><th scope="col">{t('eq.col.entries')}</th><th scope="col" aria-label={t('eq.undo')} /></tr></thead>
              <tbody>{ops.map((o) => (
                <tr key={o.id} className={o.status === 'cancelled' ? 'excluido' : ''}>
                  <td><span className="codigo">{o.code}</span></td>
                  <td>{shortDate(o.op_date)}</td>
                  <td>{t(`eq.kind.${o.kind}`)}{o.status === 'cancelled' && <span className="etiqueta etiqueta-texto"> {t('eq.cancelled')}</span>}</td>
                  <td>{(o.entry_ids ?? []).map(entryLink).filter(Boolean).reduce((acc, x) => (acc.length ? [...acc, ' · ', x] : [x]), [])}</td>
                  <td>
                    {canWrite && o.id === lastId && confirming !== o.id && <button type="button" className="secundario" disabled={busy} onClick={() => setConfirming(o.id)}>↩ {t('eq.undo')}</button>}
                    {confirming === o.id && (
                      <div className="anular" role="alertdialog" aria-label={t('eq.confirmUndo')}>
                        <p>{t('eq.confirmUndo').replace('{c}', o.code)}</p>
                        <div className="fila">
                          <button type="button" className="secundario" onClick={() => setConfirming(null)}>{t('cancel')}</button>
                          <button type="button" disabled={busy} onClick={() => undo(o.id)}>{t('eq.undo')}</button>
                        </div>
                      </div>
                    )}
                  </td>
                </tr>))}</tbody>
            </table>
          </div>
        )}
        <p className="ayuda">{t('eq.undoHelp')}</p>
      </section>
    </>
  )
}
