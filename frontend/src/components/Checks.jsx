import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { money, shortDate } from '../format'
import { workDate } from '../workDate'
import { companyPath } from '../router'
import { checksSummary } from '../controlled'
import Link from './Link'
import Term from './Term'
import ErrorBox from './ErrorBox'

const ICONS = { ok: '✓', info: 'ℹ', warning: '⚠', error: '✕' }
// Comprobaciones cuyo detalle es una lista de asientos (con enlace a su ficha)
const BY_ENTRY = ['vat_input', 'vat_output', 'tax_quota', 'withholdings', 'tax_territory', 'controlled']

// COMPROBACIONES (v0.33.0): los controles posteriores de los ERP españoles (A3, Sage), a una fecha.
// La base de datos los calcula (erp.run_audit_checks, 0037) y aquí se enseñan con el porqué, el detalle enlazado
// y la pantalla donde se arregla. Arriba, el MODO de las cuentas controladas (0036): estricto (SAP / BC) o guiado.
export default function Checks({ company, readOnly, onChanged }) {
  const { t, language } = useI18n()
  const [date, setDate] = useState(workDate(company))
  const [years, setYears] = useState([])
  const [rows, setRows] = useState(null)
  const [concepts, setConcepts] = useState({})
  const [error, setError] = useState('')
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    supabase.from('fiscal_years').select('year, starting_date, ending_date').eq('company_id', company.id)
      .then(({ data }) => setYears(data ?? []))
    supabase.from('audit_checks').select('code, concept')
      .then(({ data }) => setConcepts(Object.fromEntries((data ?? []).map((r) => [r.code, r.concept]))))
  }, [company.id])

  // El ejercicio es el que contiene la fecha (si no hay, el año natural)
  const fy = years.find((y) => date >= y.starting_date && date <= y.ending_date)
  const year = fy?.year ?? Number(String(date).slice(0, 4))

  useEffect(() => {
    if (!date) return
    let alive = true
    setRows(null)
    supabase.rpc('run_audit_checks', { p_company: company.id, p_year: year, p_to_date: date }).then(({ data, error }) => {
      if (!alive) return
      if (error) { setError(error.message); setRows([]) } else { setError(''); setRows(data ?? []) }
    })
    return () => { alive = false }
  }, [company.id, year, date])

  async function setMode(mode) {
    setSaving(true); setError('')
    const { error } = await supabase.rpc('set_control_mode', { p_company: company.id, p_mode: mode })
    setSaving(false)
    if (error) return setError(error.message)
    onChanged?.({ ...company, control_mode: mode })
  }

  const en = language === 'en'
  const m = (v) => money(v, language)
  const tax = company.tax_territory === 'canary_islands' ? 'IGIC' : 'IVA'
  const screenLabel = (id) => t(`nav.${id}.label`).replace('{tax}', tax).replace('{form}', tax === 'IGIC' ? '420' : '303')
  const mode = company.control_mode ?? 'guided'
  const canChange = !readOnly && company.my_role === 'admin'
  const sum = checksSummary(rows ?? [])
  const entryLink = (d) => (
    <Link to={companyPath(company.id, `asiento/${year}/${d.entry_no}`)} className="enlace">{d.entry_no}</Link>
  )

  function detail(r) {
    const d = r.details ?? []
    if (!d.length) return null
    let head, body
    if (BY_ENTRY.includes(r.code)) {
      head = [t('chk.col.entry'), t('chk.col.date'), t('chk.col.account'), r.code === 'controlled' ? t('chk.col.module') : t('chk.col.amount'), t('chk.col.source')]
      body = d.map((x) => [entryLink(x), shortDate(x.posting_date), x.account_no,
        r.code === 'controlled' ? (x.modules ?? []).map((mm) => t(`ctl.module.${mm}`)).join(' / ')
          : r.code === 'tax_territory' ? `${x.tax_code} · ${m(x.amount)}`
          : r.code === 'tax_quota' ? t('chk.quotaCell').replace('{a}', m(x.amount)).replace('{b}', m(x.tax_base))
              .replace('{r}', Number(x.rate_pct).toLocaleString(en ? 'en-GB' : 'es-ES')).replace('{e}', m(x.expected))
          : m(x.amount),
        x.source ? t(`chk.source.${x.source}`) : t('chk.source.manual')])
    } else if (r.code === 'partners') {
      head = [t('chk.col.partner'), t('chk.col.account'), t('chk.col.pending'), t('chk.col.balance'), t('chk.col.difference')]
      body = d.map((x) => [x.partner_name, x.account_no, m(x.pending), m(x.balance), <strong key="d">{m(x.amount)}</strong>])
    } else if (['assets_ledger', 'adjustments_ledger', 'provisions_ledger', 'inventory_ledger', 'payroll_ledger'].includes(r.code)) {
      head = [t('chk.col.account'), t('chk.col.cards'), t('chk.col.balance'), t('chk.col.difference')]
      body = d.map((x) => [`${x.account_no} ${x.account_name}`, m(x.book), m(x.balance), <strong key="d">{m(x.amount)}</strong>])
    } else if (r.code === 'provisions_review') {
      head = [t('chk.col.provision'), t('chk.col.lastMovement'), t('chk.col.balance')]
      body = d.map((x) => [`${x.code} · ${x.name}`, x.last_date ? shortDate(x.last_date) : '—', m(x.amount)])
    } else if (r.code === 'accruals_unreversed') {
      head = [t('chk.col.accrual'), t('chk.col.cutoff'), t('chk.col.amount')]
      body = d.map((x) => [`${x.code} · ${x.name}`, shortDate(x.cutoff_date), m(x.amount)])
    } else if (r.code === 'impairments_collected') {
      head = [t('chk.col.impairment'), t('chk.col.invoice'), t('chk.col.partner'), t('chk.col.amount')]
      body = d.map((x) => [x.code, x.invoice_no, x.partner_name, m(x.amount)])
    } else if (r.code === 'assets_pending') {
      head = [t('chk.col.asset'), t('chk.col.pendingDepr'), t('chk.col.lastDepr')]
      body = d.map((x) => [`${x.code} · ${x.name}`, m(x.amount), x.last_period ? shortDate(x.last_period) : '—'])
    } else {
      head = [t('chk.col.account'), t('chk.col.balance'), t('chk.col.expected'), t('chk.col.reclass')]
      body = d.map((x) => [
        <Link key="a" to={companyPath(company.id, `reports/mayor/${x.account_no}/${year}`)} className="enlace">
          {x.account_no} {x.account_name}</Link>,
        <span key="b" className={x.severity === 'error' ? 'vencida' : ''}>{m(x.amount)}</span>,
        t(`chk.nature.${x.expected}`), x.reclass_to ?? '—'])
    }
    return (
      <details className="comprobacion-detalle" open={d.length <= 5}>
        <summary>{r.items === 1 ? t('chk.seeCase') : t('chk.seeCases').replace('{n}', r.items)}{r.items > d.length ? ` · ${t('chk.firstN').replace('{n}', d.length)}` : ''}</summary>
        <div className="tabla-ancha" tabIndex={0} role="region" aria-label={en ? r.title_en : r.title}>
          <table>
            <thead><tr>{head.map((h) => <th key={h} scope="col">{h}</th>)}</tr></thead>
            <tbody>{body.map((cells, i) => <tr key={i}>{cells.map((c, j) => <td key={j}>{c}</td>)}</tr>)}</tbody>
          </table>
        </div>
      </details>
    )
  }

  return (
    <>
      <section className="tarjeta comprobaciones">
        <h2>{t('chk.title')}</h2>
        <p className="ayuda">{t('chk.intro')}</p>
        <label className="campo-fecha">{t('chk.date')}
          <input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
        </label>
        {rows && rows.length > 0 && (
          <p className="resumen-comprobaciones" role="status">
            {['error', 'warning', 'info', 'ok'].filter((s) => sum[s]).map((s) => (
              <span key={s} className={`insignia-estado ${s}`}>{ICONS[s]} {t(`chk.count.${s}`).replace('{n}', sum[s])}</span>
            ))}
          </p>
        )}
        <ErrorBox error={error} company={company} />
      </section>

      {rows === null ? <p className="ayuda">{t('loadingData')}…</p> : (
        <ul className="lista-comprobaciones">
          {rows.map((r) => (
            <li key={r.code} className={`comprobacion ${r.status}`}>
              <div className="comprobacion-cabecera">
                <span className={`insignia-estado ${r.status}`} aria-label={t(`chk.status.${r.status}`)}>{ICONS[r.status]}</span>
                <strong>{en ? r.title_en : r.title}</strong>
                {concepts[r.code] && <Term id={concepts[r.code]}>{t('ctl.what')}</Term>}
              </div>
              {r.status === 'ok' ? <p className="ayuda">{t(`chk.ok.${r.code}`)}</p> : (<>
                <p>{en ? r.why_en : r.why}</p>
                {r.book != null && (
                  <dl className="cifras-comprobacion">
                    <div><dt>{t(`chk.book.${r.code}`)}</dt><dd>{m(r.book)}</dd></div>
                    <div><dt>{t(`chk.ledger.${r.code}`)}</dt><dd>{m(r.ledger)}</dd></div>
                    <div className="diferencia"><dt>{t('chk.col.difference')}</dt><dd>{m(r.difference)}</dd></div>
                  </dl>
                )}
                {detail(r)}
                <p className="comprobacion-arreglo">💡 {en ? r.fix_en : r.fix}</p>
                <Link to={companyPath(company.id, r.screen)} className="boton secundario">{t('err.goTo')} {screenLabel(r.screen)} →</Link>
              </>)}
            </li>
          ))}
        </ul>
      )}

      {/* Modo de las cuentas controladas: lo cambia el administrador */}
      <section className="tarjeta modo-control">
        <h2>{t('controlModeLabel')} <Term id="controlMode">{t('ctl.what')}</Term></h2>
        <p className="ayuda">{t('chk.modeIntro')}</p>
        <div className="opciones-modo" role="radiogroup" aria-label={t('controlModeLabel')}>
          {['strict', 'guided'].map((cm) => (
            <label key={cm} className={mode === cm ? 'opcion-modo activa' : 'opcion-modo'}>
              <input type="radio" name="modo-control" value={cm} checked={mode === cm}
                     disabled={!canChange || saving} onChange={() => setMode(cm)} />
              <span>
                <strong>{t(`controlMode.${cm}.label`)}</strong>
                <small>{t(`controlMode.${cm}.help`)}</small>
              </span>
            </label>
          ))}
        </div>
        {!canChange && <p className="ayuda">{t('chk.modeAdminOnly')}</p>}
      </section>
    </>
  )
}
