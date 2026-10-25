import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { money, shortDate } from '../format'
import { companyPath } from '../router'
import { workDate } from '../workDate'
import { KINDS, assetShare, balanced, concessionEntry, emptyForm, imputationEntry, payload, unconditionalEntry, undoable } from '../grants'
import Link from './Link'
import Sources from './Sources'
import ErrorBox from './ErrorBox'

// SUBVENCIONES (v0.44.0): de capital y a la explotación (PGC, NRV 18.ª). La base de datos contabiliza (0064 y 0065):
// la concesión al patrimonio neto (grupo 9) neta de su impuesto futuro (8301 / 479), o a resultados (740) si es a la
// explotación; la reintegrable como deuda (522 / 172) hasta que se cumple la condición; y cada cierre la parte del año
// a resultados (840 / 746) con la amortización del activo que financia. Al cierre del ejercicio los grupos 8 y 9 se
// regularizan contra la 130, y la baja del activo en Inmovilizado imputa lo que quede.
// En BC y SAP no hay módulo estándar de subvenciones: se registran en el diario general.
export default function Grants({ company, readOnly }) {
  const { t, language } = useI18n()
  const today = workDate(company)
  const [grants, setGrants] = useState(null)
  const [assets, setAssets] = useState([])
  const [selected, setSelected] = useState(null)
  const [events, setEvents] = useState([])
  const [entryNos, setEntryNos] = useState({})
  const [form, setForm] = useState(() => emptyForm(today))
  const [opDate, setOpDate] = useState(today)
  const [yeDate, setYeDate] = useState(`${today.slice(0, 4)}-12-31`)
  const [ye, setYe] = useState(null)
  const [confirming, setConfirming] = useState(null)   // 'create' | 'collect' | 'unconditional' | 'rest' | 'yearEnd' | id
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [done, setDone] = useState('')
  const [refresh, setRefresh] = useState(0)
  const m = (v) => money(v, language)
  const canWrite = !readOnly

  useEffect(() => {
    let alive = true
    Promise.all([
      supabase.rpc('grant_status', { p_company: company.id }),
      supabase.from('v_fixed_assets').select('id, code, name, cost, status, asset_account_no').eq('company_id', company.id).order('code'),
    ]).then(([g, a]) => {
      if (!alive) return
      if (g.error) return setError(g.error.code === 'PGRST202' ? t('gr.dbMissing') : g.error.message)
      setGrants(g.data ?? []); setAssets((a.data ?? []).filter((x) => x.status === 'active'))
    })
    return () => { alive = false }
  }, [company.id, refresh])   // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!selected) return undefined
    let alive = true
    supabase.from('grant_events').select('id, grant_id, seq, kind, event_date, amount, tax_amount, entry_id, status').eq('grant_id', selected).order('seq', { ascending: false })
      .then(async ({ data }) => {
        const ev = (data ?? []).filter((r) => r.grant_id === selected)
        const ids = ev.map((r) => r.entry_id).filter(Boolean)
        const { data: je } = ids.length ? await supabase.from('journal_entries').select('id, entry_no, posting_date').in('id', ids) : { data: [] }
        if (!alive) return
        setEvents(ev); setEntryNos(Object.fromEntries((je ?? []).map((r) => [r.id, [String(r.posting_date).slice(0, 4), r.entry_no]])))
      })
    return () => { alive = false }
  }, [selected, refresh])

  useEffect(() => {
    let alive = true
    supabase.rpc('grant_year_end_preview', { p_company: company.id, p_date: yeDate })
      .then(({ data, error }) => { if (alive) setYe(error ? null : data) })
    return () => { alive = false }
  }, [company.id, yeDate, refresh])

  async function run(fn, args, ok) {
    setBusy(true); setError(''); setDone('')
    const { data, error } = await supabase.rpc(fn, args)
    setBusy(false); setConfirming(null)
    if (error) return setError(error.message)
    ok?.(data); setRefresh((x) => x + 1)
  }
  const create = () => run('grant_create', { p: payload(form, company.id) }, (d) => {
    setDone(t('gr.created').replace('{c}', d.code).replace('{n}', d.entry_no)); setSelected(d.grant_id); setForm(emptyForm(today))
  })
  const collect = () => run('grant_collect', { p: { grant_id: selected, date: opDate } }, (d) => setDone(t('gr.collected').replace('{n}', d.entry_no)))
  const uncond = () => run('grant_unconditional', { p: { grant_id: selected, date: opDate } }, (d) => setDone(t('gr.unconditionalDone').replace('{n}', d.entry_no)))
  const rest = () => run('grant_impute_rest', { p: { grant_id: selected, date: opDate } }, (d) => setDone(t('gr.restDone').replace('{m}', m(d.amount)).replace('{n}', d.entry_no)))
  const undo = () => run('grant_cancel', { p_grant: selected }, (d) => setDone(t('gr.undone').replace('{k}', t(`gr.ev.${d.kind}`))))
  const yearEnd = () => run('grant_year_end', { p_company: company.id, p_date: yeDate }, (d) => setDone(t('gr.yearEndDone').replace('{n}', d.entries)))

  const g = (grants ?? []).find((x) => x.grant_id === selected)
  const lastId = undoable(events)
  const preview = concessionEntry(form)
  const asset = assets.find((a) => a.id === form.asset_id)
  const field = (k, label, extra = {}) => (
    <label>{label}<input inputMode="decimal" value={form[k] ?? ''} onChange={(e) => setForm({ ...form, [k]: e.target.value })} {...extra} /></label>
  )
  const entryTable = (lines, caption) => (
    <div className="tabla-ancha" tabIndex={0} role="region" aria-label={caption}>
      <table className="informe">
        <caption>{caption}</caption>
        <thead><tr><th scope="col">{t('account')}</th><th scope="col" className="num">{t('debit')}</th><th scope="col" className="num">{t('credit')}</th></tr></thead>
        <tbody>{lines.map((l) => (
          <tr key={l.account + l.debit + l.credit}><td><span className="codigo">{l.account}</span> {t(`gr.account.${l.account}`)}</td>
            <td className="num">{l.debit ? m(l.debit) : ''}</td><td className="num">{l.credit ? m(l.credit) : ''}</td></tr>))}</tbody>
      </table>
      {!balanced(lines) && <p className="aviso">{t('gr.unbalanced')}</p>}
    </div>
  )
  const confirmBox = (key, text, action, label) => confirming === key && (
    <div className="anular" role="alertdialog" aria-label={text}>
      <p>{text}</p>
      <div className="fila">
        <button type="button" className="secundario" onClick={() => setConfirming(null)}>{t('cancel')}</button>
        <button type="button" disabled={busy} onClick={action}>{label}</button>
      </div>
    </div>
  )
  const action = (key, label, onClick, text) => (confirming !== key
    ? <button type="button" className="secundario" disabled={busy} onClick={() => setConfirming(key)}>{label}</button>
    : confirmBox(key, text, onClick, label))
  const entryLink = (id) => {
    const [y, n] = entryNos[id] ?? []
    return n ? <Link className="enlace" to={companyPath(company.id, `asiento/${y}/${n}`)}>{n}</Link> : null
  }

  return (
    <>
      <section className="tarjeta subvenciones">
        <div className="titulo-modelo"><h2>{t('gr.title')}</h2><Sources ids={['pgc']} /></div>
        <p className="ayuda">{t('gr.intro')}</p>
        <ErrorBox error={error} company={company} />
        {done && <p className="exito" role="status">✓ {done}</p>}
      </section>

      <section className="tarjeta">
        <h3>{t('gr.listTitle')}</h3>
        {grants && grants.length === 0 && <p className="ayuda">{t('gr.listNone')}</p>}
        {grants && grants.length > 0 && (
          <>
            <p className="ayuda">{t('gr.listHelp')}</p>
            <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('gr.listTitle')}>
              <table className="informe">
                <thead><tr><th scope="col">{t('gr.col.code')}</th><th scope="col">{t('gr.col.description')}</th><th scope="col" className="num">{t('gr.col.amount')}</th>
                  <th scope="col" className="num">{t('gr.col.imputed')}</th><th scope="col" className="num">{t('gr.col.pending')}</th><th scope="col" className="num">{t('gr.col.deferred')}</th></tr></thead>
                <tbody>{grants.map((x) => (
                  <tr key={x.grant_id} className={x.grant_id === selected ? 'seleccionado' : ''}>
                    <td><button type="button" className="secundario codigo" aria-pressed={x.grant_id === selected}
                      aria-label={`${t(x.grant_id === selected ? 'gr.hide' : 'gr.see')} ${x.code}`} onClick={() => setSelected(x.grant_id === selected ? null : x.grant_id)}>{x.code}</button></td>
                    <td>{x.description}<br /><small className="articulo">{t(`gr.kind.${x.kind}`)}{x.grantor ? ` · ${x.grantor}` : ''}{x.asset_code ? ` · ${x.asset_code}` : ''}
                      {x.refundable && !x.unconditional ? ` · ${t('gr.refundableBadge')}` : ''}{!x.collected ? ` · ${t('gr.notCollected')}` : ''}{x.status === 'imputed' ? ` · ${t('gr.imputedBadge')}` : ''}</small></td>
                    <td className="num">{m(x.amount)}</td>
                    <td className="num">{x.kind === 'capital' ? m(x.imputed) : ''}</td>
                    <td className="num">{x.kind === 'capital' ? m(x.pending) : ''}</td>
                    <td className="num">{x.kind === 'capital' ? m(x.deferred_tax) : ''}</td>
                  </tr>))}</tbody>
              </table>
            </div>
          </>
        )}
      </section>

      {g && (
        <section className="tarjeta">
          <h3>{g.code} · {g.description}</h3>
          <p className="ayuda">{t(`gr.detailHelp.${g.kind}`).replace('{a}', g.asset_code ? `${g.asset_code} · ${g.asset_name}` : '').replace('{r}', `${Number(g.tax_rate)} %`)}</p>
          {canWrite && g.status === 'active' && (
            <>
              <div className="rejilla-tres">
                <label>{t('gr.f.opDate')}<input type="date" value={opDate} onChange={(e) => { setConfirming(null); setOpDate(e.target.value) }} /></label>
              </div>
              {g.refundable && !g.unconditional && (
                <>
                  {entryTable(unconditionalEntry(g), t('gr.entry.unconditional'))}
                  {action('unconditional', t('gr.unconditional'), uncond, t('gr.confirmUnconditional').replace('{d}', shortDate(opDate)))}
                </>
              )}
              <div className="fila">
                {!g.collected && action('collect', t('gr.collect').replace('{m}', m(g.amount)), collect, t('gr.confirmCollect').replace('{m}', m(g.amount)).replace('{d}', shortDate(opDate)))}
                {g.kind === 'capital' && g.unconditional && Number(g.pending) > 0 &&
                  action('rest', t('gr.rest'), rest, t('gr.confirmRest').replace('{m}', m(g.pending)).replace('{d}', shortDate(opDate)))}
              </div>
              {g.kind === 'capital' && g.unconditional && <p className="ayuda">{t('gr.restHelp')}</p>}
            </>
          )}

          <h4>{t('gr.eventsTitle')}</h4>
          <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('gr.eventsTitle')}>
            <table className="informe">
              <thead><tr><th scope="col">{t('gr.e.date')}</th><th scope="col">{t('gr.e.kind')}</th><th scope="col" className="num">{t('gr.e.amount')}</th>
                <th scope="col" className="num">{t('gr.e.tax')}</th><th scope="col">{t('gr.e.entry')}</th><th scope="col" aria-label={t('gr.undo')} /></tr></thead>
              <tbody>{events.map((e) => (
                <tr key={e.id} className={e.status === 'cancelled' ? 'excluido' : ''}>
                  <td>{shortDate(e.event_date)}</td>
                  <td>{t(`gr.ev.${e.kind}`)}{e.status === 'cancelled' && <span className="etiqueta etiqueta-texto"> {t('gr.cancelled')}</span>}</td>
                  <td className="num">{m(e.amount)}</td><td className="num">{Number(e.tax_amount) ? m(e.tax_amount) : ''}</td>
                  <td>{e.entry_id ? entryLink(e.entry_id) : ''}</td>
                  <td>
                    {canWrite && e.id === lastId && confirming !== e.id && <button type="button" className="secundario" disabled={busy} onClick={() => setConfirming(e.id)}>↩ {t('gr.undo')}</button>}
                    {confirmBox(e.id, t(e.kind === 'concession' ? 'gr.confirmUndoStart' : 'gr.confirmUndo').replace('{k}', t(`gr.ev.${e.kind}`)), undo, t('gr.undo'))}
                  </td>
                </tr>))}</tbody>
            </table>
          </div>
          <p className="ayuda">{t('gr.undoHelp')}</p>
        </section>
      )}

      {canWrite && (
        <section className="tarjeta">
          <h3>{t('gr.newTitle')}</h3>
          <div className="rejilla-tres">
            <label>{t('gr.f.kind')}
              <select value={form.kind} onChange={(e) => setForm({ ...form, kind: e.target.value })}>
                {KINDS.map((k) => <option key={k} value={k}>{t(`gr.kind.${k}`)}</option>)}
              </select>
            </label>
            <label>{t('gr.f.description')}<input maxLength={120} value={form.description} placeholder={t(`gr.f.descPh.${form.kind}`)} onChange={(e) => setForm({ ...form, description: e.target.value })} /></label>
            <label>{t('gr.f.grantor')}<input maxLength={80} value={form.grantor} onChange={(e) => setForm({ ...form, grantor: e.target.value })} /></label>
            {field('amount', t('gr.f.amount'))}
            <label>{t('gr.f.date')}<input type="date" value={form.date} onChange={(e) => setForm({ ...form, date: e.target.value })} /></label>
            {form.kind === 'capital' && (
              <label>{t('gr.f.asset')}
                <select value={form.asset_id} onChange={(e) => setForm({ ...form, asset_id: e.target.value })}>
                  <option value="">{t('gr.f.choose')}</option>
                  {assets.map((a) => <option key={a.id} value={a.id}>{a.code} · {a.name} ({m(a.cost)})</option>)}
                </select>
              </label>
            )}
            {form.kind === 'capital' && field('tax_rate', t('gr.f.taxRate'))}
            {form.refundable && <label>{t('gr.f.conditionDue')}<input type="date" value={form.condition_due} onChange={(e) => setForm({ ...form, condition_due: e.target.value })} /></label>}
          </div>
          <div className="opciones-subvencion">
            <label className="opcion"><input type="checkbox" checked={form.refundable} onChange={(e) => setForm({ ...form, refundable: e.target.checked })} /> {t('gr.f.refundable')}</label>
            <label className="opcion"><input type="checkbox" checked={form.collected} onChange={(e) => setForm({ ...form, collected: e.target.checked })} /> {t('gr.f.collected')}</label>
          </div>
          <p className="ayuda">{t(form.refundable ? 'gr.help.refundable' : `gr.help.${form.kind}`)}</p>
          {form.kind === 'capital' && assets.length === 0 && <p className="aviso-modo">📌 {t('gr.noAssets')} <Link className="enlace" to={companyPath(company.id, 'assets')}>{t('nav.assets.label')} →</Link></p>}
          {form.kind === 'capital' && asset && assetShare(form.amount, asset.cost) > 100 && <p className="aviso" role="alert">⚠ {t('gr.exceeds').replace('{m}', m(asset.cost))}</p>}
          {form.kind === 'capital' && asset && assetShare(form.amount, asset.cost) <= 100 && <p className="ayuda">{t('gr.assetPct').replace('{p}', assetShare(form.amount, asset.cost).toLocaleString(language === 'en' ? 'en-GB' : 'es-ES')).replace('{a}', asset.code)}</p>}
          {preview.length > 0 && entryTable(preview, t('gr.entry.concession'))}
          {confirming !== 'create'
            ? <button type="button" disabled={busy || preview.length === 0 || !form.description.trim() || !form.date || (form.kind === 'capital' && (!form.asset_id || (asset && assetShare(form.amount, asset.cost) > 100))) || (form.refundable && !form.condition_due)}
                onClick={() => setConfirming('create')}>{t('gr.create')}</button>
            : confirmBox('create', t('gr.confirmCreate').replace('{d}', shortDate(form.date)), create, t('gr.create'))}
        </section>
      )}

      <section className="tarjeta">
        <h3>{t('gr.yearEndTitle')}</h3>
        <p className="ayuda">{t('gr.yearEndHelp')}</p>
        <div className="rejilla-tres">
          <label>{t('gr.f.yearEndDate')}<input type="date" value={yeDate} onChange={(e) => { setConfirming(null); setYeDate(e.target.value) }} /></label>
        </div>
        {ye && ye.grants.length === 0 && <p className="ayuda">{t('gr.yearEndNone')}</p>}
        {ye && ye.grants.length > 0 && (
          <>
            <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('gr.yearEndTitle')}>
              <table className="informe">
                <thead><tr><th scope="col">{t('gr.col.code')}</th><th scope="col" className="num">{t('gr.y.pct')}</th><th scope="col" className="num">{t('gr.y.imputation')}</th>
                  <th scope="col" className="num">{t('gr.y.tax')}</th><th scope="col">{t('gr.y.note')}</th></tr></thead>
                <tbody>{ye.grants.map((x) => (
                  <tr key={x.grant_id}>
                    <td><span className="codigo">{x.code}</span> {x.description}</td>
                    <td className="num">{x.pct != null ? `${Number(x.pct).toLocaleString(language === 'en' ? 'en-GB' : 'es-ES', { maximumFractionDigits: 2 })} %` : '—'}</td>
                    <td className="num">{Number(x.imputation) ? m(x.imputation) : '—'}</td>
                    <td className="num">{Number(x.tax) ? m(x.tax) : '—'}</td>
                    <td>{x.depreciation_pending ? <span className="aviso">⚠ {t('gr.y.depreciationPending').replace('{a}', x.asset_code)}</span>
                      : !x.unconditional ? t('gr.y.refundable') : ''}</td>
                  </tr>))}
                  <tr className="total"><td>{t('gr.y.total')}</td><td /><td className="num">{m(ye.imputation_total)}</td><td className="num">{m(ye.tax_total)}</td><td /></tr>
                </tbody>
              </table>
            </div>
            {Number(ye.imputation_total) > 0 && entryTable(imputationEntry(ye.imputation_total, ye.tax_total), t('gr.entry.imputation'))}
          </>
        )}
        {ye && ye.depreciation_pending > 0 && <p className="aviso-modo">📌 {t('gr.depreciateFirst')} <Link className="enlace" to={companyPath(company.id, 'assets')}>{t('nav.assets.label')} →</Link></p>}
        {canWrite && ye && ye.grants.length > 0 && (confirming !== 'yearEnd'
          ? <button type="button" disabled={busy || ye.depreciation_pending > 0 || (Number(ye.imputation_total) === 0 && Number(ye.tax_total) === 0)} onClick={() => setConfirming('yearEnd')}>{t('gr.yearEnd')}</button>
          : confirmBox('yearEnd', t('gr.confirmYearEnd').replace('{d}', shortDate(yeDate)), yearEnd, t('gr.yearEnd')))}
        {ye && ye.grants.length > 0 && !ye.depreciation_pending && Number(ye.imputation_total) === 0 && Number(ye.tax_total) === 0 && <p className="ayuda">✓ {t('gr.yearEndUpToDate')}</p>}
        <p className="ayuda">{t('gr.closingHelp')} <Link className="enlace" to={companyPath(company.id, 'ecpn')}>{t('nav.ecpn.label')} →</Link></p>
      </section>
    </>
  )
}
