import { Fragment, useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { money } from '../format'

// Balance de situación y Cuenta de Pérdidas y Ganancias (modelo PYMES del PGC)
//   statement: 'balance' | 'pyg' · columnas ejercicio actual y anterior, como en las cuentas anuales
export default function FinancialStatements({ company, statement }) {
  const { t, language } = useI18n()
  const [years, setYears] = useState([])
  const [year, setYear] = useState(new Date().getFullYear())
  const [toDate, setToDate] = useState('')
  const [hideZero, setHideZero] = useState(true)
  const [rows, setRows] = useState([])
  const [open, setOpen] = useState({})           // partida → cuentas que la forman (drill-down)
  const [error, setError] = useState('')

  useEffect(() => {
    supabase.from('fiscal_years').select('year').eq('company_id', company.id).order('year')
      .then(({ data, error }) => {
        if (error) return setError(error.message)
        setYears(data.map((r) => r.year))
        if (data.length && !data.some((r) => r.year === Number(year))) setYear(data[data.length - 1].year)
      })
  }, [company.id])

  useEffect(() => {
    setOpen({})
    supabase.rpc('financial_statement', {
      p_company: company.id, p_year: Number(year), p_statement: statement, p_to_date: toDate || null,
    }).then(({ data, error }) => (error ? setError(error.message) : (setError(''), setRows(data))))
  }, [company.id, year, toDate, statement])

  // Las cuentas anuales muestran los negativos entre paréntesis: (1.234,00)
  const m = (v) => (Number(v) < 0 ? `(${money(-v, language)})` : money(v, language))
  const label = (r) => (language === 'en' ? r.label_en : r.label)

  async function toggle(code) {
    if (open[code]) return setOpen({ ...open, [code]: null })
    const { data, error } = await supabase.rpc('fs_line_accounts', {
      p_company: company.id, p_year: Number(year), p_statement: statement, p_code: code, p_to_date: toDate || null,
    })
    if (error) return setError(error.message)
    setOpen({ ...open, [code]: data })
  }

  const amount = (code) => Number(rows.find((r) => r.code === code)?.amount ?? 0)
  const difference = statement === 'balance' ? amount('ACT') - amount('PNP') : 0
  const visible = rows.filter((r) => !hideZero || r.is_total || Number(r.amount) !== 0 || Number(r.amount_prev) !== 0)

  return (
    <section className="tarjeta">
      <h2>{statement === 'balance' ? t('balanceSheet') : t('incomeStatement')}</h2>
      <p className="ayuda">{statement === 'balance' ? t('balanceSheetHelp') : t('incomeStatementHelp')}</p>
      <div className="rejilla-tres">
        <label>{t('year')}
          <select value={year} onChange={(e) => setYear(e.target.value)}>
            {years.map((y) => <option key={y} value={y}>{y}</option>)}
          </select>
        </label>
        <label>{t('toDate')}<input type="date" value={toDate} onChange={(e) => setToDate(e.target.value)} /></label>
        <label className="opcion">
          <input type="checkbox" checked={hideZero} onChange={(e) => setHideZero(e.target.checked)} /> {t('hideZeroLines')}
        </label>
      </div>
      {error && <p className="aviso">⚠ {error}</p>}

      {statement === 'balance' && rows.length > 0 && (
        <div className={Math.abs(difference) < 0.005 ? 'cuadre ok' : 'cuadre descuadre'}>
          <span>{t('totalAssets')}: {m(amount('ACT'))}</span>
          <span>{t('totalEquityLiabilities')}: {m(amount('PNP'))}</span>
          <strong>{Math.abs(difference) < 0.005 ? `✓ ${t('balanced')}` : `${t('difference')}: ${m(difference)}`}</strong>
        </div>
      )}

      <div className="tabla-ancha">
        <table className="estado">
          <thead>
            <tr><th /><th className="num">{year}</th><th className="num">{Number(year) - 1}</th></tr>
          </thead>
          <tbody>
            {visible.map((r) => (
              <Fragment key={r.code}>
                <tr className={`${r.is_total ? 'total-estado' : 'partida'} nivel-${r.level}`}
                    onClick={() => !r.is_total && toggle(r.code)}>
                  <td style={{ paddingLeft: `${8 + r.level * 14}px` }}>
                    {!r.is_total && <span className="desplegar">{open[r.code] ? '▾' : '▸'}</span>} {label(r)}
                  </td>
                  <td className="num">{m(r.amount)}</td>
                  <td className="num anterior">{m(r.amount_prev)}</td>
                </tr>
                {open[r.code]?.map((a) => (
                  <tr key={`${r.code}-${a.account_no}`} className="cuenta-partida">
                    <td style={{ paddingLeft: `${28 + r.level * 14}px` }}>
                      <span className="codigo">{a.account_no}</span>
                      {language === 'en' ? a.account_name_en || a.account_name : a.account_name}
                    </td>
                    <td className="num">{m(a.amount)}</td><td />
                  </tr>
                ))}
                {open[r.code]?.length === 0 && (
                  <tr key={`${r.code}-vacio`} className="cuenta-partida"><td colSpan={3} className="ayuda">{t('noAccountsInLine')}</td></tr>
                )}
              </Fragment>
            ))}
          </tbody>
        </table>
      </div>
      <p className="ayuda">{t('statementsNote')}</p>
    </section>
  )
}