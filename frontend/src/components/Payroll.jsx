import { Fragment, useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { fetchAll } from '../paging'
import { useI18n } from '../i18n'
import { money, shortDate } from '../format'
import { workDate } from '../workDate'
import { companyPath } from '../router'
import { activeIn, monthEnd, nextMonth, nextPayment, payMonths, payrollEntryLines, payrollTotals, payslipSummary, ssBase } from '../payroll'
import Link from './Link'
import Empty from './Empty'
import Term from './Term'
import ErrorBox from './ErrorBox'

const emptyEmployee = () => ({ id: null, name: '', contract_type: 'indefinite', hire_date: '', end_date: '', monthly_salary: '',
                               extra_payments: '2', extra_prorated: false, irpf_pct: '', at_ep_pct: '1.00' })
const dec = (v) => String(v ?? '').replace(',', '.')

// NÓMINAS (v0.38.0): la nómina mensual de una pyme con su asiento del PGC (0049), para aprender el asiento, no para
// sustituir a un programa de nóminas (como el módulo de RR. HH. de Business Central o HCM de SAP, en pequeño):
//   · EMPLEADOS ficticios: salario, pagas extra (prorrateadas o no), % de IRPF (el del algoritmo de la AEAT) y AT / EP.
//   · NÓMINA DEL MES: la base de datos calcula cada recibo (cuotas con los tipos del año, IRPF, líquido) y hace el asiento:
//     640 / 642 contra 476 (cuotas), 4751 (IRPF) y 465 (líquido); las pagas extra no prorrateadas se devengan cada mes.
//   · PAGOS: el líquido (465 / 57x) y los seguros sociales del mes siguiente (476 / 57x).
export default function Payroll({ company, readOnly }) {
  const { t, language } = useI18n()
  const [employees, setEmployees] = useState([])
  const [runs, setRuns] = useState([])
  const [limits, setLimits] = useState([])
  const [cash, setCash] = useState([])
  const [month, setMonth] = useState(() => workDate(company).slice(0, 7))
  const [preview, setPreview] = useState([])        // [{ employee, calc }]
  const [form, setForm] = useState(emptyEmployee)
  const [pay, setPay] = useState(null)              // { run_id, what, payment_date, cash_account_no }
  const [open, setOpen] = useState(null)            // nómina con los recibos desplegados
  const [slips, setSlips] = useState([])
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)
  const m = (v) => money(v, language)
  const pct = (v) => `${Number(v).toLocaleString(language === 'en' ? 'en-GB' : 'es-ES', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} %`
  const digits = company.posting_account_digits ?? 8
  const name = (x) => (language === 'en' ? x.name_en || x.name : x.name)
  const ym = (d) => `${String(d).slice(5, 7)}/${String(d).slice(0, 4)}`

  async function load() {
    const [e, r, l, g] = await Promise.all([
      supabase.from('employees').select('*').eq('company_id', company.id).order('code'),
      supabase.from('v_payroll_runs').select('*').eq('company_id', company.id).order('period', { ascending: false }),
      supabase.from('ss_limits').select('*').order('year'),
      fetchAll(() => supabase.from('gl_accounts').select('id, account_no, name').eq('company_id', company.id)
        .eq('account_type', 'posting').like('account_no', '57%').order('account_no')),
    ])
    const failed = e.error || r.error || l.error || g.error
    if (failed) return setError(failed.code === 'PGRST205' || failed.code === '42P01' ? t('nom.dbMissing') : failed.message)
    setEmployees(e.data ?? []); setRuns(r.data ?? []); setLimits(l.data ?? []); setCash(g.data ?? [])
    // el mes propuesto: el siguiente a la última nómina contabilizada
    const last = (r.data ?? []).find((x) => x.status === 'posted')
    if (last) setMonth(nextMonth(last.period))
  }
  useEffect(() => { load() }, [company.id])   // eslint-disable-line react-hooks/exhaustive-deps

  // Vista previa del mes: el cálculo de cada recibo lo hace la base de datos (erp.payslip_calc)
  const period = month ? monthEnd(month) : ''
  const posted = runs.some((r) => r.status === 'posted' && r.period === period)
  const active = employees.filter((e) => month && activeIn(e, month))
  useEffect(() => {
    let alive = true
    if (!month || posted || active.length === 0) { setPreview([]); return undefined }
    Promise.all(active.map((e) => supabase.rpc('payslip_calc', { p_employee: e.id, p_period: period })))
      .then((rs) => {
        if (!alive) return
        const bad = rs.find((x) => x.error)
        if (bad) { setPreview([]); return setError(bad.error.message) }
        setPreview(active.map((e, i) => ({ employee: e, calc: rs[i].data })))
      })
    return () => { alive = false }
  }, [month, posted, employees, runs])   // eslint-disable-line react-hooks/exhaustive-deps

  async function run(fn, args, ok) {
    setBusy(true); setError(''); setMessage('')
    const r = await supabase.rpc(fn, args)
    setBusy(false)
    if (r.error) return setError(r.error.message)
    const row = Array.isArray(r.data) ? r.data[0] : r.data
    setMessage(ok(row))
    await load()
    return true
  }

  const calcs = preview.map((p) => p.calc)
  const lines = payrollEntryLines(calcs, digits)
  const totals = payrollTotals(calcs)
  const lineText = (l) => `${l.account_no} ${l.debit ? t('adj.debitShort') + ' ' + m(l.debit) : t('adj.creditShort') + ' ' + m(l.credit)}`
  const entryLink = (year, no) => (no ? <Link to={companyPath(company.id, `asiento/${year}/${no}`)} className="num-asiento">{no}</Link> : null)
  const yearOf = (d) => Number(String(d).slice(0, 4))

  const post = () => run('run_payroll', { p: { company_id: company.id, period } },
    (row) => t('nom.posted').replace('{p}', ym(period)).replace('{n}', row?.entry_no ?? '').replace('{e}', row?.employees ?? ''))
  const startPay = (r, what) => setPay({ run_id: r.id, what, cash_account_no: cash.find((a) => a.account_no.startsWith('572'))?.account_no ?? cash[0]?.account_no ?? '',
    payment_date: what === 'net' ? r.period : monthEnd(nextMonth(r.period)) })
  const doPay = (r) => run('pay_payroll', { p: pay }, (n) => { setPay(null); return t(`nom.paid.${pay.what}`).replace('{p}', ym(r.period)).replace('{n}', n) })
  const undo = (r) => run('cancel_payroll', { p_run: r.id },
    (n) => t(r.ss_payment_entry_no ? 'nom.undone.social_security' : r.net_payment_entry_no ? 'nom.undone.net' : 'nom.undone.run').replace('{p}', ym(r.period)).replace('{n}', n))

  async function toggle(r) {
    if (open === r.id) { setOpen(null); return }
    const { data, error } = await supabase.from('payslips').select('*, employees(code, name)').eq('run_id', r.id)
    if (error) return setError(error.message)
    setSlips(data ?? []); setOpen(r.id)
  }

  // ---------- Ficha del empleado ----------
  const limit = limits.find((l) => l.year === yearOf(form.hire_date || workDate(company))) ?? limits[limits.length - 1]
  const base = ssBase(form, limit)
  const save = (e) => {
    e.preventDefault()
    run('save_employee', { p: { ...(form.id ? { id: form.id } : {}), company_id: company.id, name: form.name, contract_type: form.contract_type,
      hire_date: form.hire_date, end_date: form.end_date || null, monthly_salary: dec(form.monthly_salary), extra_payments: Number(form.extra_payments),
      extra_prorated: form.extra_prorated, irpf_pct: dec(form.irpf_pct) || '0', at_ep_pct: dec(form.at_ep_pct) || '0' } },
    () => { const was = form; setForm(emptyEmployee()); return t(was.id ? 'nom.employeeSaved' : 'nom.employeeCreated').replace('{n}', was.name) })
  }
  const edit = (e) => setForm({ ...e, end_date: e.end_date ?? '', monthly_salary: String(e.monthly_salary), extra_payments: String(e.extra_payments),
    irpf_pct: String(e.irpf_pct), at_ep_pct: String(e.at_ep_pct) })
  const months = payMonths(form.extra_payments)
  const warnText = (w) => t(`nom.warn.${w.code}`).replace('{m}', m(w.min_base))

  return (
    <>
      <section className="tarjeta nominas">
        <h2><Term id="payroll">{t('nom.title')}</Term></h2>
        <p className="ayuda">{t('nom.intro')}</p>
        <ErrorBox error={error} company={company} />
        {message && <p className="exito" role="status">✓ {message}</p>}

        <h3>{t('nom.monthTitle')}</h3>
        <label className="campo-fecha">{t('nom.month')}
          <input type="month" value={month} onChange={(e) => { setMonth(e.target.value); setMessage('') }} />
        </label>
        {posted ? <p className="ayuda">✓ {t('nom.alreadyPosted').replace('{p}', ym(period))}</p>
          : active.length === 0 ? <Empty icon="👥" text={t('nom.noActive').replace('{p}', month ? ym(period) : '')} help={t('nom.noActiveHelp')} /> : (<>
            <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('nom.monthTitle')}>
              <table>
                <thead><tr>
                  <th scope="col">{t('nom.col.employee')}</th><th scope="col" className="num">{t('nom.col.earnings')}</th>
                  <th scope="col" className="num">{t('nom.col.base')}</th><th scope="col" className="num">{t('nom.col.ssEmployee')}</th>
                  <th scope="col" className="num">{t('nom.col.irpf')}</th><th scope="col" className="num">{t('nom.col.net')}</th>
                  <th scope="col" className="num"><Term id="socialSecurity">{t('nom.col.ssEmployer')}</Term></th><th scope="col" className="num">{t('nom.col.accrual')}</th>
                </tr></thead>
                <tbody>
                  {preview.map(({ employee: e, calc: c }) => (
                    <tr key={e.id}>
                      <td>{e.code} · {e.name}{(c.warnings ?? []).length > 0 && <> ⚠</>}</td>
                      <td className="num">{m(Number(c.salary) + Number(c.extra_paid))}{Number(c.extra_paid) > 0 && <><br /><small>{t('nom.extraPaid').replace('{m}', m(c.extra_paid))}</small></>}</td>
                      <td className="num">{m(c.ss_base)}</td>
                      <td className="num">{m(c.ss_employee)}</td>
                      <td className="num">{m(c.irpf)}<br /><small>{pct(c.irpf_pct)}</small></td>
                      <td className="num"><strong>{m(c.net)}</strong></td>
                      <td className="num">{m(c.ss_employer)}</td>
                      <td className="num">{Number(c.extra_accrual) ? m(c.extra_accrual) : '—'}</td>
                    </tr>))}
                  <tr className="total">
                    <td>{t('adj.total')}</td><td className="num">{m(totals.gross)}</td><td />
                    <td className="num">{m(totals.ssEmployee)}</td><td className="num">{m(totals.irpf)}</td>
                    <td className="num"><strong>{m(totals.net)}</strong></td><td className="num">{m(totals.ssEmployer)}</td><td />
                  </tr>
                </tbody>
              </table>
            </div>
            {preview.flatMap(({ employee: e, calc: c }) => (c.warnings ?? []).map((w) => (
              <p key={`${e.id}-${w.code}`} className="aviso">⚠ {e.code} · {e.name}: {warnText(w)}</p>)))}
            {lines.length > 0 && (
              <p className="vista-asiento" role="status">
                <span>{t('adj.previewEntry')} {lines.map(lineText).join(' · ')}</span>
                <span>{t('nom.costNote').replace('{m}', m(totals.expense))}</span>
              </p>
            )}
            {!readOnly && <button type="button" disabled={busy || preview.length === 0} onClick={post}>{t('nom.post').replace('{p}', ym(period))}</button>}
          </>)}
      </section>

      {/* ---------------- Nóminas contabilizadas ---------------- */}
      <section className="tarjeta">
        <h2>{t('nom.runsTitle')}</h2>
        <p className="ayuda">{t('nom.runsIntro')}</p>
        {runs.length === 0 ? <Empty icon="🧾" text={t('nom.runsEmpty')} /> : (
          <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('nom.runsTitle')}>
            <table>
              <thead><tr>
                <th scope="col">{t('nom.col.month')}</th><th scope="col" className="num">{t('nom.col.employees')}</th>
                <th scope="col" className="num">{t('nom.col.expense')}</th><th scope="col" className="num">{t('nom.col.ssTotal')}</th>
                <th scope="col" className="num">{t('nom.col.irpf')}</th><th scope="col" className="num">{t('nom.col.net')}</th>
                <th scope="col">{t('nom.col.status')}</th>{!readOnly && <th scope="col">{t('adj.col.actions')}</th>}
              </tr></thead>
              <tbody>{runs.map((r) => {
                const next = nextPayment(r)
                const paying = pay?.run_id === r.id
                return (
                  <Fragment key={r.id}>
                    <tr className={r.status === 'cancelled' ? 'anulada' : paying ? 'marcada' : ''}>
                      <td><button type="button" className="enlace" aria-expanded={open === r.id} onClick={() => toggle(r)}>{ym(r.period)}</button>
                        <br /><small>{t('fa.entry')} {entryLink(r.fiscal_year, r.entry_no)}</small></td>
                      <td className="num">{r.employees}</td>
                      <td className="num">{m(Number(r.gross) + Number(r.ss_employer))}</td>
                      <td className="num">{m(r.ss_total)}</td>
                      <td className="num">{m(r.irpf)}</td>
                      <td className="num">{m(r.net)}{Number(r.extra_paid) > 0 && <><br /><small>{t('nom.withExtra')}</small></>}</td>
                      <td>{r.status === 'cancelled' ? <span className="insignia cerrado">{t('nom.status.cancelled')}</span> : (<>
                        <span>{t('nom.netLabel')}: {r.net_payment_entry_no ? <>✓ {entryLink(yearOf(r.period), r.net_payment_entry_no)}</> : t('nom.pending')}</span><br />
                        <span>{t('nom.ssLabel')}: {r.ss_payment_entry_no ? <>✓ {entryLink(yearOf(r.period), r.ss_payment_entry_no)}</> : t('nom.pending')}</span>
                      </>)}</td>
                      {!readOnly && <td className="acciones">
                        {paying ? (
                          <div className="accion-deterioro">
                            <label>{t('nom.payDate')}<input type="date" value={pay.payment_date} onChange={(e) => setPay({ ...pay, payment_date: e.target.value })} /></label>
                            <label>{t('prv.cash')}
                              <select value={pay.cash_account_no} onChange={(e) => setPay({ ...pay, cash_account_no: e.target.value })}>
                                <option value="">—</option>
                                {cash.map((a) => <option key={a.id} value={a.account_no}>{a.account_no} · {a.name}</option>)}
                              </select></label>
                            <small>{t('adj.previewEntry')} {pay.what === 'net'
                              ? `${'465'.padEnd(digits - 1, '0')}1 ${t('adj.debitShort')} ${m(r.net)} · ${pay.cash_account_no || '57…'} ${t('adj.creditShort')} ${m(r.net)}`
                              : `${'476'.padEnd(digits - 1, '0')}1 ${t('adj.debitShort')} ${m(r.ss_total)} · ${pay.cash_account_no || '57…'} ${t('adj.creditShort')} ${m(r.ss_total)}`}</small>
                            <div className="fila">
                              <button type="button" className="secundario" onClick={() => setPay(null)}>{t('cancel')}</button>
                              <button type="button" disabled={busy || !pay.cash_account_no || !pay.payment_date} onClick={() => doPay(r)}>{t(`nom.pay.${pay.what}`)}</button>
                            </div>
                          </div>
                        ) : r.status === 'posted' && (<>
                          {next && <button type="button" className="secundario" disabled={busy} onClick={() => startPay(r, next)}>{t(`nom.pay.${next}`)}</button>}
                          <button type="button" className="secundario" disabled={busy} onClick={() => undo(r)}>↶ {t('adj.undo')}</button>
                        </>)}
                      </td>}
                    </tr>
                    {open === r.id && (
                      <tr><td colSpan={readOnly ? 7 : 8}>
                        <div className="recibos">{slips.map((s) => {
                          const p = payslipSummary(s)
                          return (
                            <article key={s.employee_id} className="recibo" aria-label={`${t('nom.payslip')} ${s.employees?.code ?? ''}`}>
                              <h4>{t('nom.payslip')} · {s.employees?.code} · {s.employees?.name}</h4>
                              <dl>
                                <div><dt>{t('nom.earnings')}</dt><dd>{m(p.earnings)}</dd></div>
                                {p.deductions.map((d) => <div key={d.concept}><dt>{name(d)} <small>{pct(d.pct)} × {m(d.base)}</small></dt><dd>−{m(d.amount)}</dd></div>)}
                                <div><dt><Term id="withholding">{t('nom.col.irpf')}</Term> <small>{pct(s.irpf_pct)}</small></dt><dd>−{m(s.irpf)}</dd></div>
                                <div className="total"><dt>{t('nom.col.net')}</dt><dd><strong>{m(p.net)}</strong></dd></div>
                              </dl>
                              <details>
                                <summary>{t('nom.employerPart').replace('{m}', m(s.ss_employer))}</summary>
                                <dl>{p.employer.map((d) => <div key={d.concept}><dt>{name(d)} <small>{pct(d.pct)} × {m(d.base)}</small></dt><dd>{m(d.amount)}</dd></div>)}</dl>
                              </details>
                              <small>{t('nom.costLine').replace('{m}', m(p.cost))}</small>
                            </article>)
                        })}</div>
                      </td></tr>
                    )}
                  </Fragment>)
              })}</tbody>
            </table>
          </div>
        )}
      </section>

      {/* ---------------- Empleados ---------------- */}
      <section className="tarjeta">
        <h2>{t('nom.employeesTitle')}</h2>
        <p className="ayuda">{t('nom.employeesIntro')}</p>
        {employees.length === 0 ? <Empty icon="👤" text={t('nom.employeesEmpty')} help={t('nom.employeesEmptyHelp')} /> : (
          <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('nom.employeesTitle')}>
            <table>
              <thead><tr>
                <th scope="col">{t('nom.col.employee')}</th><th scope="col">{t('nom.col.contract')}</th>
                <th scope="col" className="num">{t('nom.col.salary')}</th><th scope="col">{t('nom.col.extras')}</th>
                <th scope="col" className="num">{t('nom.col.irpf')}</th><th scope="col" className="num">AT / EP</th>
                <th scope="col">{t('nom.col.dates')}</th>{!readOnly && <th scope="col">{t('adj.col.actions')}</th>}
              </tr></thead>
              <tbody>{employees.map((e) => (
                <tr key={e.id} className={form.id === e.id ? 'marcada' : ''}>
                  <td>{e.code} · {e.name}</td>
                  <td>{t(`nom.contract.${e.contract_type}`)}</td>
                  <td className="num">{m(e.monthly_salary)}</td>
                  <td>{e.extra_payments} · {t(e.extra_prorated ? 'nom.prorated' : 'nom.notProrated')}</td>
                  <td className="num">{pct(e.irpf_pct)}</td>
                  <td className="num">{pct(e.at_ep_pct)}</td>
                  <td>{shortDate(e.hire_date)}{e.end_date && <> → {shortDate(e.end_date)}</>}</td>
                  {!readOnly && <td className="acciones"><button type="button" className="secundario" onClick={() => edit(e)}>{t('nom.edit')}</button></td>}
                </tr>))}</tbody>
            </table>
          </div>
        )}
      </section>

      {!readOnly && (
        <form className="tarjeta alta-activo" onSubmit={save}>
          <h2>{form.id ? t('nom.editTitle').replace('{c}', form.code) : t('nom.newTitle')}</h2>
          <p className="ayuda">{t('nom.fictitious')}</p>
          <label>{t('nom.name')}<input value={form.name} required maxLength={120} onChange={(e) => setForm({ ...form, name: e.target.value })} /></label>
          <div className="opciones-modo" role="radiogroup" aria-label={t('nom.col.contract')}>
            {['indefinite', 'temporary'].map((c) => (
              <label key={c} className={form.contract_type === c ? 'opcion-modo activa' : 'opcion-modo'}>
                <input type="radio" name="contrato" checked={form.contract_type === c} onChange={() => setForm({ ...form, contract_type: c })} />
                <span><strong>{t(`nom.contract.${c}`)}</strong><small>{t(`nom.contractHelp.${c}`)}</small></span>
              </label>
            ))}
          </div>
          <div className="rejilla-tres">
            <label>{t('nom.hireDate')}<input type="date" required disabled={!!form.id} value={form.hire_date} onChange={(e) => setForm({ ...form, hire_date: e.target.value })} /></label>
            <label>{t('nom.endDate')}<input type="date" value={form.end_date} onChange={(e) => setForm({ ...form, end_date: e.target.value })} /></label>
            <label>{t('nom.salary')}<input inputMode="decimal" required value={form.monthly_salary} onChange={(e) => setForm({ ...form, monthly_salary: e.target.value })} /></label>
          </div>
          <div className="rejilla-tres">
            <label>{t('nom.extras')}
              <select value={form.extra_payments} onChange={(e) => setForm({ ...form, extra_payments: e.target.value })}>
                {[0, 1, 2, 3, 4].map((n) => <option key={n} value={n}>{n}</option>)}
              </select></label>
            <label>{t('nom.irpf')}<input inputMode="decimal" value={form.irpf_pct} placeholder="0" onChange={(e) => setForm({ ...form, irpf_pct: e.target.value })} /></label>
            <label>{t('nom.atEp')}<input inputMode="decimal" value={form.at_ep_pct} onChange={(e) => setForm({ ...form, at_ep_pct: e.target.value })} /></label>
          </div>
          {Number(form.extra_payments) > 0 && (
            <label className="opcion">
              <input type="checkbox" checked={form.extra_prorated} onChange={(e) => setForm({ ...form, extra_prorated: e.target.checked })} />
              {t('nom.proratedLabel')}
            </label>
          )}
          <p className="ayuda">{t('nom.irpfHelp')} {t('nom.atEpHelp')}</p>
          {base.remuneration > 0 && (
            <p className="vista-asiento" role="status">
              <span>{t('nom.basePreview').replace('{s}', m(dec(form.monthly_salary))).replace('{p}', m(base.prorata)).replace('{b}', m(base.base))}</span>
              {base.capped && <span>{t('nom.capped').replace('{m}', m(limit?.max_base))}</span>}
              {base.belowMin && <span>⚠ {t('nom.warn.below_min_base').replace('{m}', m(limit?.min_base))}</span>}
              {Number(form.extra_payments) > 0 && <span>{t(form.extra_prorated ? 'nom.extrasProrated' : 'nom.extrasAccrued')
                .replace('{p}', m(base.prorata)).replace('{months}', new Intl.ListFormat(language === 'en' ? 'en-GB' : 'es-ES', { type: 'conjunction' }).format(months.map((x) => t(`nom.monthName.${x}`))))}</span>}
            </p>
          )}
          {limit && <p className="ayuda">{t('nom.ratesSource').replace('{y}', limit.year).replace('{r}', limit.legal_reference)}</p>}
          <div className="fila">
            {form.id && <button type="button" className="secundario" onClick={() => setForm(emptyEmployee())}>{t('cancel')}</button>}
            <button type="submit" disabled={busy || !form.name.trim() || !form.hire_date || !(Number(dec(form.monthly_salary)) > 0)}>
              {t(form.id ? 'nom.saveEmployee' : 'nom.createEmployee')}</button>
          </div>
        </form>
      )}
    </>
  )
}
