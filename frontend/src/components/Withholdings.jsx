import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { money } from '../format'
import ErrorBox from './ErrorBox'

const currentQuarter = () => Math.floor(new Date().getMonth() / 3) + 1

// Casillas del borrador: modelo 111 (actividades económicas, dinerarias) y modelo 115 (alquileres)
const BOXES = { 111: ['07', '08', '09'], 115: ['01', '02', '03'] }

// Retenciones IRPF del trimestre: practicadas (las ingresa la empresa: 111 / 115) y soportadas (pagos a cuenta)
// Como el informe de retenciones de A3 / Sage o el "Withholding Tax Report" (S_P00_07000134) de SAP
export default function Withholdings({ company }) {
  const { t, language } = useI18n()
  const [years, setYears] = useState([])
  const [year, setYear] = useState(new Date().getFullYear())
  const [quarter, setQuarter] = useState(currentQuarter())
  const [summary, setSummary] = useState([])
  const [detail, setDetail] = useState([])
  const [error, setError] = useState('')

  const m = (v) => money(v, language)
  const pct = (v) => `${Number(v).toLocaleString(language === 'en' ? 'en-GB' : 'es-ES')} %`

  useEffect(() => {
    supabase.from('fiscal_years').select('year').eq('company_id', company.id).order('year')
      .then(({ data, error }) => {
        if (error) return setError(error.message)
        setYears(data.map((r) => r.year))
        if (data.length && !data.some((r) => r.year === Number(year))) setYear(data[data.length - 1].year)
      })
  }, [company.id])

  useEffect(() => {
    Promise.all([
      supabase.rpc('withholding_summary', { p_company: company.id, p_year: Number(year), p_quarter: Number(quarter) }),
      supabase.from('v_withholding_register').select('*').eq('company_id', company.id)
        .eq('fiscal_year', Number(year)).eq('quarter', Number(quarter)).order('posting_date'),
    ]).then(([s, d]) => {
      const failed = s.error || d.error
      if (failed) return setError(failed.message)
      setError(''); setSummary(s.data); setDetail(d.data)
    })
  }, [company.id, year, quarter])

  const withheld = summary.filter((r) => r.side === 'withheld')
  const suffered = summary.filter((r) => r.side === 'suffered')
  const forms = [...new Set(withheld.map((r) => r.form))]
  const total = (rows, f) => rows.reduce((s, r) => s + Number(r[f]), 0)

  return (
    <>
      <section className="tarjeta">
        <h2>{t('withholdingsTitle')}</h2>
        <p className="ayuda">{t('withholdingsIntro')}</p>
        <div className="rejilla-tres">
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
      </section>

      {/* Retenciones practicadas: un borrador por modelo */}
      <section className="tarjeta">
        <h2>{t('withheldTitle')}</h2>
        {forms.length === 0 && <p className="ayuda">{t('noWithholdings')}</p>}
        {forms.map((form) => {
          const rows = withheld.filter((r) => r.form === form)
          const [b1, b2, b3] = BOXES[form] ?? ['', '', '']
          return (
            <div key={form} className="modelo-retenciones">
              <h3>{t('form')} {form} · {t(`withholdingForm.${form}`)}</h3>
              <p className="ayuda">{t('formBoxes').replace('{a}', b1).replace('{b}', b2).replace('{c}', b3)}</p>
              <div className="tabla-ancha">
              <table>
                <thead>
                  <tr>
                    <th>IRPF</th><th className="num">{t('recipients')}</th>
                    <th className="num">{t('taxBase')}</th><th className="num">{t('withheldAmount')}</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((r) => (
                    <tr key={r.withholding_code}>
                      <td>{pct(r.rate_pct)}</td><td className="num">{r.recipients}</td>
                      <td className="num">{m(r.base)}</td><td className="num">{m(r.amount)}</td>
                    </tr>
                  ))}
                  <tr className="total">
                    <td>{t('total')}</td>
                    <td className="num">{new Set(detail.filter((d) => d.side === 'withheld' && d.form === form).map((d) => d.partner_id)).size}</td>
                    <td className="num">{m(total(rows, 'base'))}</td><td className="num">{m(total(rows, 'amount'))}</td>
                  </tr>
                </tbody>
              </table>
              </div>
            </div>
          )
        })}
        <p className="ayuda">{t('withholdingPaymentHelp')}</p>
        <p className="ayuda">{t('payrollWithholdingHelp')}</p>
      </section>

      {/* Retenciones soportadas: nos las retienen los clientes (pago a cuenta del Impuesto sobre Sociedades) */}
      <section className="tarjeta">
        <h2>{t('sufferedTitle')}</h2>
        <p className="ayuda">{t('sufferedHelp')}</p>
        {suffered.length === 0 ? <p className="ayuda">{t('noWithholdings')}</p> : (
          <table>
            <tbody>
              {suffered.map((r) => (
                <tr key={r.withholding_code}>
                  <td>IRPF {pct(r.rate_pct)}</td><td className="num">{m(r.base)}</td><td className="num">{m(r.amount)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>

      <section className="tarjeta">
        <h2>{t('withholdingDetail')} ({detail.length})</h2>
        {detail.length === 0 && <p className="ayuda">{t('noWithholdings')}</p>}
        <ul>
          {detail.map((d) => (
            <li key={d.invoice_id}>
              <strong>
                <span className="codigo">{d.invoice_no}</span>
                {d.external_document_no && `${d.external_document_no} · `}{d.partner_name}
                <span className="insignia">{d.side === 'withheld' ? `${t('form')} ${d.form}` : t('suffered')}</span>
              </strong>
              <span>
                {d.posting_date} · {d.vat_registration_no ?? '—'} · IRPF {pct(d.rate_pct)} · {t('base')} {m(d.withholding_base)}
                {' · '}<strong>{m(d.withholding_amount)}</strong> · {t('entry')} {d.entry_no}
              </span>
            </li>
          ))}
        </ul>
      </section>
    </>
  )
}
