import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { money, taxLabel } from '../format'
import Empty from './Empty'
import Loading from './Loading'
import { companyPath } from '../router'
import ErrorBox from './ErrorBox'

const today = () => new Date().toISOString().slice(0, 10)
const currentQuarter = () => Math.floor(new Date().getMonth() / 3) + 1

// Liquidación trimestral de IVA (modelo 303) / IGIC (modelo 420)
// Como "Calc. and Post VAT Settlement" de Business Central
export default function TaxSettlement({ company, readOnly }) {
  const { t, language } = useI18n()
  const [types, setTypes] = useState(null)   // null = aún cargando
  const [years, setYears] = useState([])
  const [taxType, setTaxType] = useState('')
  const [year, setYear] = useState(new Date().getFullYear())
  const [quarter, setQuarter] = useState(currentQuarter())
  const [refund, setRefund] = useState(false)
  const [acceptDiff, setAcceptDiff] = useState(false)
  const [calc, setCalc] = useState(null)
  const [history, setHistory] = useState([])
  const [codes, setCodes] = useState({})
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)

  const m = (v) => money(v, language)
  const rate = (v) => `${Number(v).toLocaleString(language === 'en' ? 'en-GB' : 'es-ES')} %`

  // Impuestos configurados y ejercicios de la empresa
  useEffect(() => {
    Promise.all([
      supabase.from('v_tax_settlement_setup').select('tax_type').eq('company_id', company.id).order('tax_type'),
      supabase.from('fiscal_years').select('year').eq('company_id', company.id).order('year'),
      supabase.from('tax_codes').select('code, tax_type, rate_pct, rate_category, exemption_key'),
    ]).then(([s, y, k]) => {
      const failed = s.error || y.error || k.error
      if (failed) return setError(failed.message)
      const list = s.data.map((r) => r.tax_type)
      setTypes(list)
      setTaxType(list.includes(company.tax_territory === 'canary_islands' ? 'IGIC' : 'VAT')
        ? (company.tax_territory === 'canary_islands' ? 'IGIC' : 'VAT') : list[0] ?? '')
      setYears(y.data.map((r) => r.year))
      setCodes(Object.fromEntries(k.data.map((c) => [c.code, c])))
    })
  }, [company.id])

  async function load() {
    if (!taxType) return
    setError('')
    const [c, h] = await Promise.all([
      supabase.rpc('tax_settlement_calc', {
        p_company: company.id, p_tax_type: taxType, p_year: Number(year), p_quarter: Number(quarter), p_refund: refund,
      }),
      supabase.from('v_tax_settlements').select('*').eq('company_id', company.id).eq('tax_type', taxType)
        .order('year', { ascending: false }).order('quarter', { ascending: false }),
    ])
    if (c.error) { setCalc(null); setError(c.error.message) } else setCalc(c.data)
    if (!h.error) setHistory(h.data)
  }

  useEffect(() => { setAcceptDiff(false); load() }, [taxType, year, quarter, refund])

  async function post() {
    setError(''); setMessage(''); setBusy(true)
    const { data, error } = await supabase.rpc('post_tax_settlement', {
      p_company: company.id, p_tax_type: taxType, p_year: Number(year), p_quarter: Number(quarter),
      p_refund: refund, p_accept_difference: acceptDiff,
    }).single()
    setBusy(false)
    if (error) return setError(error.message)
    setMessage(t('settlementPosted').replace('{entry}', data.entry_no ?? '—'))
    load()
  }

  async function cancel() {
    setError(''); setMessage(''); setBusy(true)
    const { error } = await supabase.rpc('cancel_tax_settlement', { p_settlement: calc.settlement_id })
    setBusy(false)
    if (error) return setError(error.message)
    setMessage(t('settlementCancelled'))
    load()
  }

  if (types === null) return error ? <ErrorBox error={error} company={company} /> : <Loading />
  if (types.length === 0) {
    return (
      <section className="tarjeta">
        <h2>{t('taxSettlementTitle')}</h2>
        <Empty icon="🧾" text={t('noTaxSetup')} help={readOnly ? null : t('emptyTaxesHelp')}
               action={readOnly ? null : t('actionSetupTaxes')} to={companyPath(company.id, 'taxes')} />
      </section>
    )
  }

  const boxes = (side) => (calc?.boxes ?? []).filter((b) => b.side === side)
  const diff = Number(calc?.difference ?? 0)
  const final = Number(calc?.final_result ?? 0)

  return (
    <>
      <section className="tarjeta">
        <h2>{t('taxSettlementTitle')}</h2>
        <p className="ayuda">{t('taxSettlementIntro')}</p>
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
          <label>{t('quarter')}
            <select value={quarter} onChange={(e) => setQuarter(e.target.value)}>
              {[1, 2, 3, 4].map((q) => <option key={q} value={q}>{q}T</option>)}
            </select>
          </label>
        </div>
        <ErrorBox error={error} company={company} />
        {message && <p className="exito">✓ {message}</p>}
      </section>

      {calc && (
        <section className="tarjeta liquidacion-borrador">
          <h2>{t('draftForm').replace('{form}', calc.form)} · {calc.quarter}T {calc.year}</h2>
          <p className="ayuda">{calc.period_start} → {calc.period_end}</p>
          {calc.period_end >= today() && !calc.settled && <p className="aviso">⚠ {t('quarterNotEnded')}</p>}

          {['output', 'input'].map((side) => (
            <div key={side}>
              <h3>{t(`settlementSide.${side}`)}</h3>
              <table>
                <thead>
                  <tr><th>{t('taxRate')}</th><th className="num">{t('taxBase')}</th><th className="num">{t('taxAmount')}</th></tr>
                </thead>
                <tbody>
                  {boxes(side).length === 0 && <tr><td colSpan={3} className="ayuda">{t('noOperations')}</td></tr>}
                  {boxes(side).map((b) => (
                    <tr key={`${b.tax_code}-${b.kind}`}>
                      <td>
                        {b.kind === 'pro_rata' ? `${t('proRataBox')} (${rate(b.rate_pct)})`
                          : b.kind === 'surcharge' ? `${t('equivalenceSurcharge')} ${rate(b.rate_pct)}`
                          : codes[b.tax_code] ? taxLabel(codes[b.tax_code], t, language) : rate(b.rate_pct)}
                        {b.kind === 'reverse_charge' && <span className="ayuda"> · {t('selfAssessed')}</span>}
                      </td><td className="num">{b.tax_base == null ? '' : m(b.tax_base)}</td><td className="num">{m(b.tax_amount)}</td>
                    </tr>
                  ))}
                  <tr className="total">
                    <td>{t('total')}</td><td />
                    <td className="num">{m(side === 'output' ? calc.register_output : calc.register_input)}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          ))}

          <table className="resultado">
            <tbody>
              <tr><td>{t('settlementResult')}</td><td className="num">{m(calc.result)}</td></tr>
              {Number(calc.carry_available) > 0 && (
                <tr><td>{t('carryAvailable')}</td><td className="num">{m(calc.carry_available)}</td></tr>
              )}
              {Number(calc.carry_applied) > 0 && (
                <tr><td>{t('carryApplied')}</td><td className="num">− {m(calc.carry_applied)}</td></tr>
              )}
              <tr className={`total resultado-${calc.outcome}`}>
                <td>{t(`outcome.${calc.outcome}`)}</td><td className="num">{m(Math.abs(final))}</td>
              </tr>
            </tbody>
          </table>

          {calc.can_refund && !calc.settled && (
            <label className="opcion">
              <input type="checkbox" checked={refund} onChange={(e) => setRefund(e.target.checked)} />
              {t('requestRefund')}
            </label>
          )}

          {/* Cuadre del auditor: lo declarado (libro registro) frente a lo contabilizado (472/477) */}
          <div className={diff === 0 ? 'cuadre ok' : 'cuadre descuadre'}>
            <span>{t('registerVsAccounts')}</span>
            <span>{t('accountsLabel')}: {m(Number(calc.output_tax) - Number(calc.input_tax))}</span>
            <span>{t('registerLabel')}: {m(Number(calc.register_output) - Number(calc.register_input))}</span>
            <strong>{diff === 0 ? `✓ ${t('balanced')}` : `${t('difference')}: ${m(diff)}`}</strong>
          </div>
          {diff !== 0 && <p className="ayuda">{t('differenceHelp')}</p>}
          {diff !== 0 && !calc.settled && !readOnly && (
            <label className="opcion">
              <input type="checkbox" checked={acceptDiff} onChange={(e) => setAcceptDiff(e.target.checked)} />
              {t('acceptDifference')}
            </label>
          )}

          <h3>{t('settlementEntry')}</h3>
          {calc.lines.length === 0 ? <p className="ayuda">{t('noSettlementEntry')}</p> : (
            <table>
              <thead><tr><th>{t('account')}</th><th className="num">{t('debit')}</th><th className="num">{t('credit')}</th></tr></thead>
              <tbody>
                {calc.lines.map((l) => (
                  <tr key={l.account_no + l.debit + l.credit}>
                    <td><span className="codigo">{l.account_no}</span> {l.account_name}</td>
                    <td className="num">{Number(l.debit) ? m(l.debit) : ''}</td>
                    <td className="num">{Number(l.credit) ? m(l.credit) : ''}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}

          {!readOnly && (calc.settled ? (
            <div className="fila">
              <p className="exito">✓ {t('alreadySettled')}</p>
              <button type="button" className="secundario" disabled={busy} onClick={cancel}>{t('cancelSettlement')}</button>
            </div>
          ) : (
            <button type="button" disabled={busy || (diff !== 0 && !acceptDiff)} onClick={post}>
              {t('postSettlement')}
            </button>
          ))}
        </section>
      )}

      <section className="tarjeta">
        <h2>{t('settlementHistory')}</h2>
        {history.length === 0 && <p>{t('noSettlements')}</p>}
        <ul>
          {history.map((s) => (
            <li key={s.id} className={s.status === 'cancelled' ? 'bloqueado' : ''}>
              <strong>{t('form')} {s.form} · {s.quarter}T {s.year}</strong>
              <span>
                {t(`outcome.${s.outcome}`)} {m(Math.abs(s.final_result))} · {t('entry')} {s.entry_no ?? '—'}
                {s.status === 'cancelled' && ` · ${t('cancelled')}`}
                {Number(s.register_difference) !== 0 && ` · ⚠ ${t('difference')} ${m(s.register_difference)}`}
              </span>
            </li>
          ))}
        </ul>
      </section>
    </>
  )
}
