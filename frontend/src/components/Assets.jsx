import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { fetchAll } from '../paging'
import { useI18n } from '../i18n'
import { money, shortDate } from '../format'
import { workDate } from '../workDate'
import { companyPath } from '../router'
import { accumulatedAt, annualPct, assetTotals, classesFor, endOfMonth, invoiceAssetLines, isAssetAccount, taxWarnings } from '../assets'
import Link from './Link'
import Empty from './Empty'
import Term from './Term'
import ErrorBox from './ErrorBox'

const emptyForm = (date) => ({ lineKey: '', name: '', account_no: '', class_code: '', cost: '', residual: '',
                               acquisition_date: date, start_date: date, years: '', months: '' })

// INMOVILIZADO (v0.35.0): fichas de activos, amortización lineal (NRV 2.ª y 3.ª del PGC) y baja con resultado.
// Como Activos fijos de Business Central o FI-AA de SAP. La base de datos calcula y contabiliza (0041):
//   · Alta desde la línea de una factura recibida a una cuenta 2x (o a mano, para lo que ya existía)
//   · «Amortizar hasta…»: un asiento 68x / 28x con todos los activos · se deshace la última
//   · Ficha: cuadro de amortización por años · baja (siniestro, obsolescencia) o venta con su factura emitida
export default function Assets({ company, readOnly }) {
  const { t, language } = useI18n()
  const [assets, setAssets] = useState([])
  const [classes, setClasses] = useState([])
  const [accounts, setAccounts] = useState([])
  const [lines, setLines] = useState([])
  const [invoices, setInvoices] = useState([])
  const [last, setLast] = useState(null)                       // última amortización { entry_id, period_end }
  const [selectedId, setSelectedId] = useState('')
  const [schedule, setSchedule] = useState([])
  const [form, setForm] = useState(() => emptyForm(workDate(company)))
  const [deprDate, setDeprDate] = useState(() => endOfMonth(workDate(company)))
  const [disposal, setDisposal] = useState(null)               // { mode: sale | retire, date, invoice_id }
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [warnings, setWarnings] = useState([])
  const [busy, setBusy] = useState(false)
  const m = (v) => money(v, language)
  const en = language === 'en'
  const pct = (v) => Number(v).toLocaleString(en ? 'en-GB' : 'es-ES', { maximumFractionDigits: 2 })

  async function load() {
    const [a, c, g, l, i, d] = await Promise.all([
      supabase.from('v_fixed_assets').select('*').eq('company_id', company.id).order('code'),
      supabase.from('depreciation_classes').select('*').order('sort'),
      fetchAll(() => supabase.from('gl_accounts').select('id, account_no, name, name_en').eq('company_id', company.id)
        .eq('account_type', 'posting').like('account_no', '2%').order('account_no')),
      fetchAll(() => supabase.from('invoice_lines').select('invoice_id, line_no, amount, sign, gl_account_id, description')
        .eq('company_id', company.id)),
      supabase.from('v_invoices').select('id, invoice_type, document_kind, invoice_no, external_document_no, partner_name, invoice_date, description, entry_no, fiscal_year')
        .eq('company_id', company.id),
      supabase.from('asset_depreciations').select('entry_id, period_end').eq('company_id', company.id)
        .order('period_end', { ascending: false }).limit(1),
    ])
    const failed = a.error || c.error || g.error || l.error || i.error || d.error
    if (failed) return setError(failed.code === 'PGRST205' || failed.code === '42P01' ? t('fa.dbMissing') : failed.message)
    setAssets(a.data ?? []); setClasses(c.data ?? []); setAccounts(g.data ?? []); setLines(l.data ?? [])
    setInvoices(i.data ?? []); setLast(d.data?.[0] ?? null)
  }
  useEffect(() => { load() }, [company.id])   // eslint-disable-line react-hooks/exhaustive-deps

  const selected = assets.find((a) => a.id === selectedId)
  useEffect(() => {
    if (!selectedId) return
    let alive = true
    supabase.rpc('depreciation_schedule', { p_asset: selectedId }).then(({ data, error }) => {
      if (alive) { if (error) setError(error.message); else setSchedule(data ?? []) }
    })
    return () => { alive = false }
  }, [selectedId, assets])

  const tot = assetTotals(assets)
  const usedPurchase = new Set(assets.map((a) => a.invoice_id).filter(Boolean))
  const candidates = invoiceAssetLines(lines, accounts, invoices, 'purchase', usedPurchase)
  const assetAccounts = accounts.filter((a) => isAssetAccount(a.account_no))
  const life = (Number(form.years) || 0) * 12 + (Number(form.months) || 0)
  const cls = classes.find((c) => c.code === form.class_code)
  const preview = form.cost && life > 0 && form.start_date
    ? accumulatedAt(form.cost, form.residual || 0, life, form.start_date, `${form.start_date.slice(0, 4)}-12-31`) : null
  const liveWarnings = taxWarnings(cls, life)
  const warningText = (w) => t(`fa.warn.${w.code}`).replace('{r}', pct(w.rate)).replace('{m}', pct(w.max)).replace('{y}', pct(w.years)).replace('{my}', w.maxYears)

  // Elegir la línea de una factura recibida rellena la ficha (nombre, cuenta, coste, fechas y la clase fiscal de su grupo)
  function chooseLine(key) {
    const c = candidates.find((x) => x.key === key)
    if (!c) return setForm((f) => ({ ...f, lineKey: '' }))
    const first = classesFor(classes, c.account_no)[0]
    setForm((f) => ({ ...f, lineKey: key, name: c.description || c.account_name, account_no: c.account_no, cost: String(c.amount),
      acquisition_date: c.date, start_date: c.date,
      class_code: first && first.pgc_prefix === c.account_no.slice(0, 3) ? first.code : f.class_code }))
  }

  async function run(fn, ok) {
    setBusy(true); setError(''); setMessage(''); setWarnings([])
    const r = await fn()
    setBusy(false)
    if (r.error) return setError(r.error.message)
    setMessage(ok(r.data))
    await load()
  }

  const create = (e) => {
    e.preventDefault()
    const line = candidates.find((x) => x.key === form.lineKey)
    run(() => supabase.rpc('create_fixed_asset', { p: {
      company_id: company.id, name: form.name, asset_account_no: form.account_no, class_code: form.class_code || null,
      cost: form.cost.replace(',', '.'), residual_value: (form.residual || '0').replace(',', '.'),
      acquisition_date: form.acquisition_date, start_date: form.start_date, useful_life_months: life,
      invoice_id: line?.invoice_id ?? null } }), (d) => {
      const row = Array.isArray(d) ? d[0] : d
      setWarnings(row?.warnings ?? []); setForm(emptyForm(workDate(company))); setSelectedId(row?.asset_id ?? '')
      return t('fa.created').replace('{c}', row?.code ?? '')
    })
  }
  const depreciate = () => run(() => supabase.rpc('post_depreciation', { p_company: company.id, p_date: deprDate }), (d) => {
    const row = Array.isArray(d) ? d[0] : d
    return t('fa.depreciated').replace('{n}', row?.entry_no).replace('{a}', row?.assets).replace('{m}', m(row?.amount))
  })
  const undoDepreciation = () => run(() => supabase.rpc('cancel_depreciation', { p_entry: last.entry_id }), (n) => t('fa.undone').replace('{n}', n))
  const dispose = () => run(() => supabase.rpc('dispose_asset', { p: { asset_id: selected.id, disposal_date: disposal.date,
    invoice_id: disposal.mode === 'sale' ? disposal.invoice_id || null : null } }), (d) => {
    const row = Array.isArray(d) ? d[0] : d
    setDisposal(null)
    return t(Number(row?.result) < 0 ? 'fa.disposedLoss' : 'fa.disposedGain').replace('{n}', row?.entry_no)
      .replace('{v}', m(row?.net_book_value)).replace('{r}', m(Math.abs(Number(row?.result))))
  })
  const undoDisposal = () => run(() => supabase.rpc('cancel_disposal', { p_asset: selected.id }), (n) => t('fa.disposalUndone').replace('{n}', n))

  const saleLines = selected ? invoiceAssetLines(lines, accounts, invoices, 'sale', new Set(), selected.asset_account_no) : []
  const entryLink = (year, no) => (no ? <Link to={companyPath(company.id, `asiento/${year}/${no}`)} className="num-asiento">{no}</Link> : null)

  return (
    <>
      <section className="tarjeta activos">
        <h2>{t('fa.title')}</h2>
        <p className="ayuda">{t('fa.intro')}</p>
        <dl className="cifras-comprobacion">
          <div><dt>{t('fa.inUse')}</dt><dd>{tot.count}</dd></div>
          <div><dt>{t('fa.cost')}</dt><dd>{m(tot.cost)}</dd></div>
          <div><dt><Term id="depreciation">{t('fa.accumulated')}</Term></dt><dd>{m(tot.accumulated)}</dd></div>
          <div><dt>{t('fa.net')}</dt><dd>{m(tot.net)}</dd></div>
        </dl>
        {!readOnly && assets.length > 0 && (
          <div className="fila-amortizar">
            <label>{t('fa.deprUntil')}
              <input type="date" value={deprDate} onChange={(e) => setDeprDate(e.target.value)} />
            </label>
            <button type="button" disabled={busy || !deprDate} onClick={depreciate}>{t('fa.deprButton')}</button>
            {last && (
              <button type="button" className="secundario" disabled={busy} onClick={undoDepreciation}>
                ↶ {t('fa.undoLast').replace('{d}', shortDate(last.period_end))}
              </button>
            )}
          </div>
        )}
        <ErrorBox error={error} company={company} />
        {message && <p className="exito" role="status">✓ {message}</p>}
        {warnings.map((w) => <p key={w.code} className="aviso">⚠ {warningText(w)}</p>)}
      </section>

      <section className="tarjeta">
        <h2>{t('fa.list')}</h2>
        {assets.length === 0 ? <Empty icon="🏭" text={t('fa.empty')} help={t('fa.emptyHelp')} /> : (
          <ul className="lista-activos">
            {assets.map((a) => (
              <li key={a.id} className={a.id === selectedId ? 'marcada' : ''}>
                <button type="button" className="enlace" aria-expanded={a.id === selectedId}
                        onClick={() => { setSelectedId(a.id === selectedId ? '' : a.id); setDisposal(null) }}>
                  <strong>{a.code} · {a.name}</strong>
                </button>
                <span>{a.asset_account_no} · {t('fa.since')} {shortDate(a.start_date)} · {pct(annualPct(a.useful_life_months))} %
                  {a.status === 'disposed' && <> · <span className="insignia cerrado">{t('fa.disposed')}</span></>}</span>
                <span className="importes-activo">
                  <span>{t('fa.cost')} <strong>{m(a.cost)}</strong></span>
                  <span>{t('fa.accumulatedShort')} <strong>{m(a.accumulated)}</strong></span>
                  <span>{t('fa.net')} <strong>{m(a.net_book_value)}</strong></span>
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>

      {selected && (
        <section className="tarjeta ficha-activo">
          <h2>{selected.code} · {selected.name}</h2>
          <dl className="cifras-comprobacion">
            <div><dt>{t('fa.account')}</dt><dd>{selected.asset_account_no} → {selected.depreciation_account_no} / {selected.expense_account_no}</dd></div>
            <div><dt>{t('fa.lifeLabel')}</dt><dd>{t('fa.lifeValue').replace('{m}', selected.useful_life_months).replace('{p}', pct(annualPct(selected.useful_life_months)))}</dd></div>
            <div><dt>{t('fa.residual')}</dt><dd>{m(selected.residual_value)}</dd></div>
            {selected.class_code && <div><dt>{t('fa.taxClass')}</dt><dd>{en ? selected.class_name_en : selected.class_name} · {t('fa.taxMax').replace('{p}', pct(selected.max_pct))}</dd></div>}
            {selected.invoice_no && <div><dt>{t('fa.invoice')}</dt><dd>{selected.external_document_no || selected.invoice_no} · {t('fa.entry')} {entryLink(selected.invoice_year, selected.invoice_entry_no)}</dd></div>}
          </dl>
          <h3>{t('fa.schedule')}</h3>
          <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('fa.schedule')}>
            <table>
              <thead><tr><th scope="col">{t('fa.year')}</th><th scope="col" className="num">{t('fa.charge')}</th>
                <th scope="col" className="num">{t('fa.accumulatedShort')}</th><th scope="col" className="num">{t('fa.net')}</th></tr></thead>
              <tbody>{schedule.map((r) => (
                <tr key={r.year}><td>{r.year}</td><td className="num">{m(r.amount)}</td><td className="num">{m(r.accumulated)}</td>
                  <td className="num">{m(r.net_book_value)}</td></tr>))}</tbody>
            </table>
          </div>

          {selected.status === 'disposed' ? (
            <>
              <p className="aviso">{t('fa.disposedOn').replace('{d}', shortDate(selected.disposal_date))
                .replace('{p}', m(selected.disposal_price))} {t('fa.entry')} {entryLink(selected.disposal_year, selected.disposal_entry_no)}</p>
              {!readOnly && <button type="button" className="secundario" disabled={busy} onClick={undoDisposal}>↶ {t('fa.undoDisposal')}</button>}
            </>
          ) : !readOnly && (disposal ? (
            <div className="baja-activo">
              <h3>{t('fa.disposeTitle')}</h3>
              <div className="opciones-modo" role="radiogroup" aria-label={t('fa.disposeTitle')}>
                {['sale', 'retire'].map((mode) => (
                  <label key={mode} className={disposal.mode === mode ? 'opcion-modo activa' : 'opcion-modo'}>
                    <input type="radio" name="baja" checked={disposal.mode === mode} onChange={() => setDisposal({ ...disposal, mode })} />
                    <span><strong>{t(`fa.mode.${mode}`)}</strong><small>{t(`fa.modeHelp.${mode}`)}</small></span>
                  </label>
                ))}
              </div>
              <label>{t('fa.disposalDate')}
                <input type="date" value={disposal.date} onChange={(e) => setDisposal({ ...disposal, date: e.target.value })} />
              </label>
              {disposal.mode === 'sale' && (saleLines.length === 0
                ? <p className="aviso">{t('fa.noSaleInvoice').replace('{a}', selected.asset_account_no)}{' '}
                    <Link to={companyPath(company.id, 'invoices')} className="enlace">{t('pay.goInvoices')} →</Link></p>
                : (
                  <label>{t('fa.saleInvoice')}
                    <select value={disposal.invoice_id} onChange={(e) => setDisposal({ ...disposal, invoice_id: e.target.value })}>
                      <option value="">—</option>
                      {saleLines.map((l) => <option key={l.key} value={l.invoice_id}>{l.invoice_no} · {l.partner_name} · {shortDate(l.date)} · {m(l.amount)}</option>)}
                    </select>
                  </label>
                ))}
              <p className="ayuda">{t('fa.disposeHelp')}</p>
              <div className="fila">
                <button type="button" className="secundario" onClick={() => setDisposal(null)}>{t('cancel')}</button>
                <button type="button" disabled={busy || !disposal.date || (disposal.mode === 'sale' && !disposal.invoice_id)} onClick={dispose}>
                  {t(`fa.mode.${disposal.mode}`)}</button>
              </div>
            </div>
          ) : (
            <button type="button" className="secundario" onClick={() => setDisposal({ mode: 'sale', date: workDate(company), invoice_id: '' })}>
              {t('fa.disposeButton')}</button>
          ))}
        </section>
      )}

      {!readOnly && (
        <form className="tarjeta alta-activo" onSubmit={create}>
          <h2>{t('fa.newTitle')}</h2>
          <p className="ayuda">{t('fa.newIntro')}</p>
          {candidates.length > 0 && (
            <label>{t('fa.fromInvoice')}
              <select value={form.lineKey} onChange={(e) => chooseLine(e.target.value)}>
                <option value="">{t('fa.manualOption')}</option>
                {candidates.map((c) => <option key={c.key} value={c.key}>{c.invoice_no} · {c.partner_name} · {shortDate(c.date)} · {c.account_no} · {m(c.amount)}</option>)}
              </select>
            </label>
          )}
          <label>{t('fa.name')}<input value={form.name} required onChange={(e) => setForm({ ...form, name: e.target.value })} /></label>
          <div className="rejilla-tres">
            <label>{t('fa.account')}
              <select value={form.account_no} required onChange={(e) => setForm({ ...form, account_no: e.target.value })}>
                <option value="">—</option>
                {assetAccounts.map((a) => <option key={a.id} value={a.account_no}>{a.account_no} · {a.name}</option>)}
              </select>
            </label>
            <label>{t('fa.cost')}<input inputMode="decimal" required value={form.cost} onChange={(e) => setForm({ ...form, cost: e.target.value })} /></label>
            <label>{t('fa.residual')}<input inputMode="decimal" value={form.residual} placeholder="0" onChange={(e) => setForm({ ...form, residual: e.target.value })} /></label>
            <label>{t('fa.acquisition')}<input type="date" required value={form.acquisition_date} onChange={(e) => setForm({ ...form, acquisition_date: e.target.value })} /></label>
            <label>{t('fa.start')}<input type="date" required value={form.start_date} onChange={(e) => setForm({ ...form, start_date: e.target.value })} /></label>
            <label>{t('fa.taxClass')}
              <select value={form.class_code} onChange={(e) => setForm({ ...form, class_code: e.target.value })}>
                <option value="">—</option>
                {classesFor(classes, form.account_no).map((c) => <option key={c.code} value={c.code}>{en ? c.name_en : c.name} ({pct(c.max_pct)} %)</option>)}
              </select>
            </label>
            <label>{t('fa.years')}<input inputMode="numeric" value={form.years} onChange={(e) => setForm({ ...form, years: e.target.value.replace(/\D/g, '') })} /></label>
            <label>{t('fa.months')}<input inputMode="numeric" value={form.months} placeholder="0" onChange={(e) => setForm({ ...form, months: e.target.value.replace(/\D/g, '') })} /></label>
          </div>
          {life > 0 && (
            <p className="vista-asiento" role="status">
              <span>{t('fa.previewRate').replace('{p}', pct(annualPct(life)))}</span>
              {preview !== null && <span>{t('fa.previewFirst').replace('{y}', form.start_date.slice(0, 4)).replace('{m}', m(preview))}</span>}
            </p>
          )}
          {liveWarnings.map((w) => <p key={w.code} className="aviso">⚠ {warningText(w)}</p>)}
          <p className="ayuda">{t('fa.startHelp')}</p>
          <button type="submit" disabled={busy || !form.name || !form.account_no || !form.cost || life <= 0}>{t('fa.create')}</button>
        </form>
      )}
    </>
  )
}
