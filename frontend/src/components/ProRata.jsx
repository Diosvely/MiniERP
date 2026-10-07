import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { money } from '../format'

// Prorrata general del IVA / IGIC: porcentaje provisional del año y regularización con el definitivo en el 4T
// (como la "Prorrata" de A3ECO / Sage: % provisional en la ficha y asistente de regularización anual)
export default function ProRata({ company, readOnly }) {
  const { t, language } = useI18n()
  const isAdmin = !readOnly && company.my_role === 'admin'
  const canWrite = !readOnly && ['admin', 'accountant'].includes(company.my_role)
  const [types, setTypes] = useState([])
  const [taxType, setTaxType] = useState('')
  const [years, setYears] = useState([])
  const [year, setYear] = useState(new Date().getFullYear())
  const [rows, setRows] = useState([])
  const [pct, setPct] = useState('')
  const [calc, setCalc] = useState(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')

  const m = (v) => money(v, language)
  const p = (v) => `${Number(v).toLocaleString(language === 'en' ? 'en-GB' : 'es-ES')} %`

  useEffect(() => {
    Promise.all([
      supabase.from('v_tax_settlement_setup').select('tax_type').eq('company_id', company.id).order('tax_type'),
      supabase.from('fiscal_years').select('year').eq('company_id', company.id).order('year'),
    ]).then(([s, y]) => {
      const failed = s.error || y.error
      if (failed) return setError(failed.message)
      const list = s.data.map((r) => r.tax_type)
      setTypes(list)
      const home = company.tax_territory === 'canary_islands' ? 'IGIC' : 'VAT'
      setTaxType(list.includes(home) ? home : list[0] ?? '')
      setYears(y.data.map((r) => r.year))
      if (y.data.length && !y.data.some((r) => r.year === Number(year))) setYear(y.data[y.data.length - 1].year)
    })
  }, [company.id])

  async function load() {
    if (!taxType) return
    const { data, error } = await supabase.from('v_pro_rata').select('*')
      .eq('company_id', company.id).eq('tax_type', taxType).order('year', { ascending: false })
    if (error) return setError(error.message)
    setRows(data)
    const current = data.find((r) => r.year === Number(year))
    setPct(current ? String(current.provisional_pct) : '')
    if (current) {
      const c = await supabase.rpc('pro_rata_calc', { p_company: company.id, p_tax_type: taxType, p_year: Number(year) })
      if (c.error) { setCalc(null); setError(c.error.message) } else setCalc(c.data)
    } else setCalc(null)
  }

  useEffect(() => { setMessage(''); load() }, [taxType, year])

  async function run(fn, args, ok) {
    setError(''); setMessage(''); setBusy(true)
    const { error } = await supabase.rpc(fn, args)
    setBusy(false)
    if (error) return setError(error.message)
    setMessage(ok)
    load()
  }

  const base = { p_company: company.id, p_tax_type: taxType, p_year: Number(year) }
  const save = () => run('set_pro_rata', { ...base, p_pct: Number(String(pct).replace(',', '.')) }, t('proRataSaved'))
  const remove = () => run('set_pro_rata', { ...base, p_pct: null }, t('proRataRemoved'))
  const post = () => run('post_pro_rata_regularization', base, t('proRataPosted'))
  const cancel = () => run('cancel_pro_rata_regularization', base, t('proRataCancelled'))

  if (types.length === 0) {
    return <section className="tarjeta"><h2>{t('proRataTitle')}</h2><p>{t('noTaxSetup')}</p></section>
  }
  if (company.vat_regime === 'equivalence_surcharge') {
    return <section className="tarjeta"><h2>{t('proRataTitle')}</h2><p>{t('proRataNotForRE')}</p></section>
  }

  const adj = Number(calc?.adjustment ?? 0)

  return (
    <>
      <section className="tarjeta">
        <h2>{t('proRataTitle')}</h2>
        <p className="ayuda">{t('proRataIntro')}</p>
        <div className="rejilla-tres">
          <label>{t('tax')}
            <select value={taxType} onChange={(e) => setTaxType(e.target.value)}>
              {types.map((ty) => <option key={ty} value={ty}>{t(`taxType.${ty}`)}</option>)}
            </select>
          </label>
          <label>{t('year')}
            <select value={year} onChange={(e) => setYear(e.target.value)}>
              {years.map((y) => <option key={y} value={y}>{y}</option>)}
            </select>
          </label>
          <label>{t('provisionalPct')}
            <input inputMode="decimal" value={pct} disabled={!isAdmin || calc?.regularized}
                   placeholder={t('noProRata')} onChange={(e) => setPct(e.target.value)} />
          </label>
        </div>
        {isAdmin && !calc?.regularized && (
          <div className="fila">
            <button type="button" disabled={busy || pct === ''} onClick={save}>{t('saveProRata')}</button>
            {rows.some((r) => r.year === Number(year)) && (
              <button type="button" className="secundario" disabled={busy} onClick={remove}>{t('removeProRata')}</button>
            )}
          </div>
        )}
        <p className="ayuda">{t('provisionalHelp')}</p>
        {error && <p className="aviso">⚠ {error}</p>}
        {message && <p className="exito">✓ {message}</p>}
      </section>

      {calc && (
        <section className="tarjeta">
          <h2>{t('proRataRegularization')} {year}</h2>
          <table className="resultado">
            <tbody>
              <tr><td>{t('operationsWithRight')}</td><td className="num">{m(calc.operations_with_right)}</td></tr>
              <tr><td>{t('operationsTotal')}</td><td className="num">{m(calc.operations_total)}</td></tr>
              <tr className="total"><td>{t('definitivePct')}</td><td className="num">{p(calc.definitive_pct)}</td></tr>
              <tr><td>{t('provisionalPct')}</td><td className="num">{p(calc.provisional_pct)}</td></tr>
              <tr><td>{t('inputTaxYear')}</td><td className="num">{m(calc.input_tax)}</td></tr>
              <tr><td>{t('deductedYear')}</td><td className="num">{m(calc.deducted)}</td></tr>
              <tr><td>{t('shouldDeduct')}</td><td className="num">{m(calc.should_deduct)}</td></tr>
              <tr className={`total ${adj < 0 ? 'resultado-payable' : 'resultado-refund'}`}>
                <td>{adj > 0 ? t('adjustmentPositive') : adj < 0 ? t('adjustmentNegative') : t('adjustmentNone')}</td>
                <td className="num">{m(adj)}</td>
              </tr>
            </tbody>
          </table>
          <p className="ayuda">{t('definitiveHelp')}</p>

          {calc.lines.length > 0 && (
            <>
              <h3>{t('regularizationEntry')} · 31/12/{year}</h3>
              <table>
                <thead><tr><th>{t('account')}</th><th className="num">{t('debit')}</th><th className="num">{t('credit')}</th></tr></thead>
                <tbody>
                  {calc.lines.map((l) => (
                    <tr key={l.account_no}>
                      <td><span className="codigo">{l.account_no}</span> {l.account_no.startsWith('634') ? t('negativeAdjustment')
                        : l.account_no.startsWith('639') ? t('positiveAdjustment') : t('inputTax')}</td>
                      <td className="num">{Number(l.debit) ? m(l.debit) : ''}</td>
                      <td className="num">{Number(l.credit) ? m(l.credit) : ''}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </>
          )}

          {calc.regularized ? (
            <>
              <p className="exito">✓ {t('proRataDone').replace('{n}', calc.entry_no ?? '—').replace('{p}', p(calc.definitive_pct))
                .replace('{y}', Number(year) + 1)}</p>
              {canWrite && !calc.q4_settled && (
                <button type="button" className="secundario" disabled={busy} onClick={cancel}>↩ {t('undoProRata')}</button>
              )}
            </>
          ) : canWrite && (
            calc.q4_settled
              ? <p className="aviso">⚠ {t('proRataQ4Settled')}</p>
              : <button type="button" disabled={busy} onClick={post}>{t('postProRata')}</button>
          )}
        </section>
      )}

      <section className="tarjeta">
        <h2>{t('proRataHistory')}</h2>
        {rows.length === 0 && <p>{t('noProRataYears')}</p>}
        <ul>
          {rows.map((r) => (
            <li key={r.year}>
              <strong>{r.year}</strong>
              <span>
                {t('provisionalPct')} {p(r.provisional_pct)}
                {r.definitive_pct != null && ` · ${t('definitivePct')} ${p(r.definitive_pct)} · ${m(r.regularization_amount)}`}
                {r.entry_no && ` · ${t('entry')} ${r.entry_no}`}
              </span>
            </li>
          ))}
        </ul>
      </section>
    </>
  )
}
