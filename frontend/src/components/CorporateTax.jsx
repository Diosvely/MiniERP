import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { money } from '../format'
import { companyPath } from '../router'
import { workYear } from '../workDate'
import { downloadXlsx, fileName } from '../exportXlsx'
import { REGIMES, breakdown, entriesPreview, expense, sign } from '../corporateTax'
import Link from './Link'
import Sources from './Sources'
import ErrorBox from './ErrorBox'
import ReportActions from './ReportActions'

// IMPUESTO SOBRE SOCIEDADES (v0.41.0): el último paso del cierre de una sociedad, antes de la regularización a la 129.
// La base de datos calcula (0057) y contabiliza (0058); aquí se ve el cálculo entero, se deciden los ajustes, el
// régimen y el crédito fiscal, y se contabiliza o se deshace. Como el «tax provision» de SAP; BC no lo trae de serie.
export default function CorporateTax({ company, readOnly }) {
  const { t, language } = useI18n()
  const [years, setYears] = useState([])
  const [year, setYear] = useState(() => workYear(company))
  const [calc, setCalc] = useState(null)
  const [entries, setEntries] = useState({})     // { current, deferred } → nº de asiento (contabilizado)
  const [busy, setBusy] = useState(false)
  const [confirming, setConfirming] = useState(null)   // 'post' | 'cancel'
  const [error, setError] = useState('')
  const [manual, setManual] = useState(null)     // ajuste manual en edición
  const m = (v) => money(v, language)
  const pct = (v) => `${Number(v).toLocaleString(language === 'en' ? 'en-GB' : 'es-ES', { maximumFractionDigits: 2 })} %`

  useEffect(() => {
    supabase.from('fiscal_years').select('year, status').eq('company_id', company.id).order('year')
      .then(({ data }) => setYears(data ?? []))
  }, [company.id])

  // Lee el cálculo y, si está contabilizado, los números de sus dos asientos (no toca el estado: lo hace apply)
  async function fetchCalc() {
    const { data, error } = await supabase.rpc('corporate_tax_calc', { p_company: company.id, p_year: Number(year) })
    if (error) return { error: error.code === 'PGRST202' ? t('ct.dbMissing') : error.message }
    if (data?.status !== 'posted') return { data, entries: {} }
    const { data: r } = await supabase.from('corporate_tax_returns').select('current_entry_id, deferred_entry_id').eq('id', data.return_id).maybeSingle()
    const ids = [r?.current_entry_id, r?.deferred_entry_id].filter(Boolean)
    const { data: e } = ids.length ? await supabase.from('journal_entries').select('id, entry_no').in('id', ids) : { data: [] }
    const no = (id) => (e ?? []).find((x) => x.id === id)?.entry_no
    return { data, entries: { current: no(r?.current_entry_id), deferred: no(r?.deferred_entry_id) } }
  }
  function apply(r) {
    if (r.error) { setCalc(null); return setError(r.error) }
    setError(''); setCalc(r.data); setEntries(r.entries)
  }
  const load = () => fetchCalc().then(apply)
  useEffect(() => {
    let alive = true
    fetchCalc().then((r) => { if (alive) apply(r) })
    return () => { alive = false }
  }, [company.id, year])   // eslint-disable-line react-hooks/exhaustive-deps

  async function run(fn, args) {
    setBusy(true); setError('')
    const { error } = await supabase.rpc(fn, args)
    setBusy(false); setConfirming(null)
    if (error) return setError(error.message)
    await load()
  }
  const prepare = () => run('corporate_tax_prepare', { p_company: company.id, p_year: Number(year) })
  const settings = (regime, recognize) => run('corporate_tax_settings', { p_return: calc.return_id, p_regime: regime, p_recognize: recognize })
  const include = (id, v) => run('corporate_tax_include', { p_adjustment: id, p_included: v })
  async function saveManual() {
    await run('corporate_tax_manual', { p: { return_id: calc.return_id, kind: manual.kind, direction: manual.direction, concept: manual.concept,
      amount: Number(String(manual.amount).replace(/\./g, '').replace(',', '.')), article: manual.article } })
    setManual(null)
  }

  const status = calc?.status ?? 'none'
  const draft = status === 'draft'
  const canWrite = !readOnly
  const editable = canWrite && draft
  const hint = calc?.hint
  const preview = entriesPreview(calc)

  function excel() {
    const rows = [...breakdown(calc).map((r) => ({ concept: t(`ct.row.${r.key}`), amount: r.amount })),
      ...expense(calc).map((r) => ({ concept: t(`ct.row.${r.key}`), amount: r.amount })),
      ...(calc?.adjustments ?? []).filter((a) => a.included).map((a) => ({ concept: `${t(`ct.kind.${a.kind}`)} · ${a.concept}`, amount: sign(a) * a.amount }))]
    return downloadXlsx({ title: `${t('ct.title')} ${year} · ${company.name}`, subtitle: t(`ct.regime.${calc.regime}`), sheet: 'IS',
      file: fileName(t('ct.title'), company.name, String(year)),
      columns: [{ header: t('ct.col.concept'), key: 'concept', type: 'text', width: 70 }, { header: t('ct.col.amount'), key: 'amount', type: 'money' }], rows })
  }

  return (
    <>
      <section className="tarjeta impuesto-sociedades">
        <div className="titulo-modelo"><h2>{t('ct.title')}</h2><Sources ids={['lis', 'pgc']} /></div>
        <p className="ayuda">{t('ct.intro')}</p>
        <div className="rejilla-tres">
          <label>{t('year')}
            <select value={year} onChange={(e) => { setConfirming(null); setManual(null); setYear(e.target.value) }}>
              {(years.length ? years.map((y) => y.year) : [year]).map((y) => <option key={y} value={y}>{y}</option>)}
            </select>
          </label>
        </div>
        <ErrorBox error={error} company={company} />
        {calc && (
          <p className={`estado-is ${status}`} role="status">
            {t(`ct.status.${status}`)}
            {status === 'posted' && entries.current && <> · <Link className="enlace" to={companyPath(company.id, `asiento/${year}/${entries.current}`)}>{t('ct.entryCurrent')} {entries.current}</Link></>}
            {status === 'posted' && entries.deferred && <> · <Link className="enlace" to={companyPath(company.id, `asiento/${year}/${entries.deferred}`)}>{t('ct.entryDeferred')} {entries.deferred}</Link></>}
          </p>
        )}
        {canWrite && status === 'none' && calc && <button type="button" disabled={busy} onClick={prepare}>{t('ct.prepare')}</button>}
      </section>

      {calc && (
        <>
          <section className="tarjeta">
            <h3>{t('ct.settingsTitle')}</h3>
            <label>{t('ct.regimeLabel')}
              <select value={calc.regime} disabled={!editable || busy} onChange={(e) => settings(e.target.value, calc.recognize_loss_credit)}>
                {REGIMES.map((r) => <option key={r} value={r}>{t(`ct.regime.${r}`)}</option>)}
              </select>
            </label>
            {hint && <p className="ayuda">{t('ct.hint').replace('{m}', m(hint.turnover)).replace('{y}', hint.basis_year).replace('{r}', t(`ct.regime.${hint.suggested}`))}</p>}
            {calc.brackets?.length > 0 && <p className="ayuda">{t('ct.rates')}: {calc.brackets.map((b) => `${pct(b.rate)} × ${m(b.base)}`).join(' + ')} ({t('ct.ratesYear')} {calc.rates_year})</p>}
            <label className="opcion">
              <input type="checkbox" checked={calc.recognize_loss_credit} disabled={!editable || busy} onChange={(e) => settings(calc.regime, e.target.checked)} />
              {t('ct.recognize')}
            </label>
            <p className="ayuda">{t('ct.recognizeHelp')}</p>
          </section>

          <section className="tarjeta">
            <h3>{t('ct.adjTitle')}</h3>
            <p className="ayuda">{t('ct.adjHelp')}</p>
            {calc.adjustments.length === 0 ? <p className="ayuda">{t('ct.adjNone')}</p> : (
              <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('ct.adjTitle')}>
                <table className="casillas">
                  <thead><tr><th scope="col">{t('ct.col.include')}</th><th scope="col">{t('ct.col.concept')}</th><th scope="col">{t('ct.col.kind')}</th><th scope="col" className="num">{t('ct.col.amount')}</th></tr></thead>
                  <tbody>{calc.adjustments.map((a, i) => (
                    <tr key={a.id ?? i} className={a.included ? '' : 'excluido'}>
                      <td>
                        {a.auto
                          ? <input type="checkbox" checked={a.included} disabled={!editable || busy || !a.id} aria-label={`${t('ct.col.include')}: ${a.concept}`}
                                   onChange={(e) => include(a.id, e.target.checked)} />
                          : editable && <button type="button" className="secundario" disabled={busy} aria-label={`${t('ct.delete')}: ${a.concept}`}
                                                onClick={() => run('corporate_tax_manual', { p: { id: a.id, delete: true } })}>✕</button>}
                      </td>
                      <td>{a.concept}{a.article && <small className="articulo"> · {a.article}</small>}{!a.auto && <span className="etiqueta etiqueta-texto"> {t('ct.manual')}</span>}</td>
                      <td>{t(`ct.kind.${a.kind}`)}</td>
                      <td className="num">{sign(a) > 0 ? '+' : '−'} {m(a.amount)}</td>
                    </tr>))}</tbody>
                </table>
              </div>
            )}
            {editable && !manual && (
              <button type="button" className="secundario" onClick={() => setManual({ kind: 'permanent', direction: 'increase', concept: '', amount: '', article: '' })}>
                + {t('ct.addManual')}
              </button>
            )}
            {editable && manual && (
              <form className="ajuste-manual" onSubmit={(e) => { e.preventDefault(); saveManual() }}>
                <label>{t('ct.col.concept')}<input required maxLength={200} value={manual.concept} placeholder={t('ct.manualPlaceholder')} onChange={(e) => setManual({ ...manual, concept: e.target.value })} /></label>
                <div className="rejilla-tres">
                  <label>{t('ct.col.kind')}
                    <select value={manual.kind} onChange={(e) => setManual({ ...manual, kind: e.target.value })}>
                      {['permanent', 'temporary'].map((k) => <option key={k} value={k}>{t(`ct.kind.${k}`)}</option>)}
                    </select>
                  </label>
                  <label>{t('ct.direction')}
                    <select value={manual.direction} onChange={(e) => setManual({ ...manual, direction: e.target.value })}>
                      {['increase', 'decrease'].map((k) => <option key={k} value={k}>{t(`ct.dir.${k}`)}</option>)}
                    </select>
                  </label>
                  <label>{t('ct.col.amount')}<input required inputMode="decimal" value={manual.amount} onChange={(e) => setManual({ ...manual, amount: e.target.value })} /></label>
                </div>
                <label>{t('ct.article')}<input maxLength={80} value={manual.article} placeholder="LIS art. 15.c" onChange={(e) => setManual({ ...manual, article: e.target.value })} /></label>
                <div className="fila">
                  <button type="button" className="secundario" onClick={() => setManual(null)}>{t('cancel')}</button>
                  <button type="submit" disabled={busy}>{t('ct.saveManual')}</button>
                </div>
              </form>
            )}
          </section>

          <section className="tarjeta">
            <h3>{t('ct.calcTitle')} · {t(`ct.regime.${calc.regime}`)}</h3>
            <ReportActions info={`${company.name} · ${t('ct.title')} ${year}`} onExcel={excel} />
            <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('ct.calcTitle')}>
              <table className="casillas">
                <tbody>
                  {breakdown(calc).map((r) => (
                    <tr key={r.key} className={r.total ? 'total' : ''}>
                      <td>{t(`ct.row.${r.key}`)}{r.key === 'losses' && calc.losses_available > 0 && <small className="articulo"> · {t('ct.lossesInfo').replace('{a}', m(calc.losses_available)).replace('{l}', m(calc.losses_limit))}</small>}</td>
                      <td className="num">{m(r.amount)}</td>
                    </tr>))}
                </tbody>
              </table>
            </div>
            <p className={`resultado-modelo ${calc.outcome}`}>{t(`ct.outcome.${calc.outcome}`).replace('{m}', m(Math.abs(calc.differential)))}</p>
            <h3>{t('ct.expenseTitle')}</h3>
            <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('ct.expenseTitle')}>
              <table className="casillas">
                <tbody>{expense(calc).map((r) => (
                  <tr key={r.key} className={r.total ? 'total' : ''}><td>{t(`ct.row.${r.key}`)}</td><td className="num">{m(r.amount)}</td></tr>))}</tbody>
              </table>
            </div>
            <p className="ayuda">{t('ct.expenseHelp').replace('{r}', pct(calc.deferred_rate))}</p>
            {calc.warnings?.length > 0 && (
              <ul className="comprobaciones">
                {calc.warnings.map((w, i) => (
                  <li key={i} className="warning"><span className="icono">⚠</span> {t(`ct.warn.${w.code}`).replace('{r}', w.suggested ? t(`ct.regime.${w.suggested}`) : '')
                    .replace('{m}', m(w.turnover ?? w.amount ?? 0))}</li>))}
              </ul>
            )}
          </section>

          <section className="tarjeta">
            <h3>{status === 'posted' ? t('ct.entriesPosted') : t('ct.entriesPreview')}</h3>
            {[['current', preview.current], ['deferred', preview.deferred]].map(([k, lines]) => (
              <div key={k}>
                <h4>{t(`ct.entry.${k}`)}</h4>
                {lines.length === 0 ? <p className="ayuda">{t('ct.noEntry')}</p> : (
                  <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t(`ct.entry.${k}`)}>
                    <table className="informe">
                      <thead><tr><th scope="col">{t('account')}</th><th scope="col" className="num">{t('debit')}</th><th scope="col" className="num">{t('credit')}</th></tr></thead>
                      <tbody>{lines.map((l) => (
                        <tr key={l.account}><td><span className="codigo">{l.account}</span> {t(`ct.account.${l.account}`)}</td>
                          <td className="num">{l.debit ? m(l.debit) : ''}</td><td className="num">{l.credit ? m(l.credit) : ''}</td></tr>))}</tbody>
                    </table>
                  </div>
                )}
              </div>
            ))}
            {canWrite && draft && confirming !== 'post' && <button type="button" disabled={busy} onClick={() => setConfirming('post')}>{t('ct.post')}</button>}
            {canWrite && status === 'posted' && confirming !== 'cancel' && <button type="button" className="secundario" disabled={busy} onClick={() => setConfirming('cancel')}>↩ {t('ct.cancel')}</button>}
            {confirming && (
              <div className="anular" role="alertdialog" aria-label={t(`ct.confirm.${confirming}`)}>
                <p>{t(`ct.confirm.${confirming}`).replace('{y}', year)}</p>
                <div className="fila">
                  <button type="button" className="secundario" onClick={() => setConfirming(null)}>{t('cancel')}</button>
                  <button type="button" disabled={busy} onClick={() => run(confirming === 'post' ? 'corporate_tax_post' : 'corporate_tax_cancel', { p_company: company.id, p_year: Number(year) })}>
                    {t(confirming === 'post' ? 'ct.post' : 'ct.cancel')}
                  </button>
                </div>
              </div>
            )}
            <p className="ayuda">{t('ct.beforeClosing')} <Link className="enlace" to={companyPath(company.id, 'closing')}>{t('nav.closing.label')} →</Link></p>
          </section>
        </>
      )}
    </>
  )
}
