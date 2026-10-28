import { Fragment, useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { workDate, workYear } from '../workDate'
import { money } from '../format'
import { changePct, prevCutoff } from '../compare'
import ErrorBox from './ErrorBox'
import ReportActions from './ReportActions'
import { downloadXlsx, fileName } from '../exportXlsx'
import DateField from './DateField'
import MonthPicker from './MonthPicker'
import SimulationToggle, { SimulationBanner } from './SimulationToggle'
import { moveToYear, reportBase, simTitle } from '../reportPeriod'

// Balance de situación y Cuenta de Pérdidas y Ganancias (modelo PYMES del PGC)
//   statement: 'balance' | 'pyg' · columnas ejercicio actual y anterior, como en las cuentas anuales
// v0.30.0 · ANÁLISIS HORIZONTAL: variación en importe y en % frente al ejercicio anterior, y el anterior también al
// desplegar una partida. Con fecha de corte (0032): la PyG se compara con el mismo periodo del año anterior y el
// Balance con el cierre del ejercicio anterior (NIC 34). La variación no lleva color: que suba un gasto o un ingreso
// no es "bueno" o "malo" por sí solo; el signo y el % bastan para ver dónde mirar.
// v0.51.0 · «hasta» con la fecha rápida y los botones de mes, y la simulación con los asientos en edición (ADR 0051).
export default function FinancialStatements({ company, statement }) {
  const { t, language } = useI18n()
  const [years, setYears] = useState([])
  const [year, setYear] = useState(() => workYear(company))   // año de la fecha de trabajo
  const [toDate, setToDate] = useState('')
  const [hideZero, setHideZero] = useState(true)
  const [sim, setSim] = useState(false)          // simulación: incluir los asientos en edición
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
      p_company: company.id, p_year: Number(year), p_statement: statement, p_to_date: toDate || null, p_drafts: sim,
    }).then(({ data, error }) => (error ? setError(error.message) : (setError(''), setRows(data))))
  }, [company.id, year, toDate, statement, sim])

  // Las cuentas anuales muestran los negativos entre paréntesis: (1.234,00)
  const m = (v) => (Number(v) < 0 ? `(${money(-v, language)})` : money(v, language))
  const label = (r) => (language === 'en' ? r.label_en : r.label)

  // ¿Hay ejercicio anterior? Si no, no se enseñan sus columnas (estarían a cero y confundirían)
  const hasPrev = years.includes(Number(year) - 1)
  // Fecha de corte del ejercicio anterior: Balance → su cierre (null); PyG → la misma fecha un año antes
  const prevDate = prevCutoff(statement, toDate)
  const shortDate = (d) => new Date(`${d}T00:00:00`).toLocaleDateString(language === 'en' ? 'en-GB' : 'es-ES')

  async function toggle(code) {
    if (open[code]) return setOpen({ ...open, [code]: null })
    const ask = (y, d) => supabase.rpc('fs_line_accounts', {
      p_company: company.id, p_year: y, p_statement: statement, p_code: code, p_to_date: d, p_drafts: sim,
    })
    const [now, before] = await Promise.all([ask(Number(year), toDate || null),
      hasPrev ? ask(Number(year) - 1, prevDate) : Promise.resolve({ data: [] })])
    if (now.error || before.error) return setError((now.error || before.error).message)
    // Una fila por subcuenta con los dos importes (puede existir solo en uno de los dos ejercicios)
    const byAccount = new Map()
    for (const a of now.data) byAccount.set(a.account_no, { ...a, amount_prev: 0 })
    for (const a of before.data) {
      const row = byAccount.get(a.account_no)
      if (row) row.amount_prev = a.amount
      else byAccount.set(a.account_no, { ...a, amount: 0, amount_prev: a.amount })
    }
    setOpen({ ...open, [code]: [...byAccount.values()].sort((a, b) => a.account_no.localeCompare(b.account_no)) })
  }

  // Variación: importe y % sobre el valor absoluto del anterior (si el anterior es 0, el % no tiene sentido)
  const diff = (r) => Number(r.amount) - Number(r.amount_prev)
  const pct = (r) => changePct(r.amount, r.amount_prev, language)

  // Excel: las partidas visibles con su sangría, los dos ejercicios y la variación (números, no texto)
  const title = simTitle(statement === 'balance' ? t('balanceSheet') : t('incomeStatement'), sim, t('sim.prefix'))
  const filters = `${t('year')} ${year}${toDate ? ` · ${t('fsAt').replace('{d}', shortDate(toDate))}` : ''}`
  const exportExcel = () => downloadXlsx({
    title: `${title} · ${company.name ?? ''}`, subtitle: filters, sheet: title,
    file: fileName(title, company.name, year, toDate),
    columns: [
      { header: t('fsLine'), key: 'label', type: 'text', width: 60 },
      { header: String(year), key: 'amount', type: 'money' },
      ...(hasPrev ? [
        { header: String(Number(year) - 1), key: 'amount_prev', type: 'money' },
        { header: t('fsChange'), key: 'change', type: 'money' },
        { header: '%', key: 'pct', type: 'pct' },
      ] : []),
    ],
    rows: visible.map((r) => ({
      label: `${'   '.repeat(r.level)}${label(r)}`, amount: r.amount, amount_prev: r.amount_prev, change: diff(r),
      pct: Math.abs(Number(r.amount_prev)) < 0.005 ? null : diff(r) / Math.abs(Number(r.amount_prev)),
    })),
  })

  const amount = (code) => Number(rows.find((r) => r.code === code)?.amount ?? 0)
  const difference = statement === 'balance' ? amount('ACT') - amount('PNP') : 0
  const visible = rows.filter((r) => !hideZero || r.is_total || Number(r.amount) !== 0 || Number(r.amount_prev) !== 0)

  return (
    <section className="tarjeta">
      <div className="titulo-informe">
        <h2>{statement === 'balance' ? t('balanceSheet') : t('incomeStatement')}</h2>
        {rows.length > 0 && <ReportActions onExcel={exportExcel} info={`${sim ? `${t('sim.prefix')} · ` : ''}${company.name} · ${filters}`} />}
      </div>
      <p className="ayuda">{statement === 'balance' ? t('balanceSheetHelp') : t('incomeStatementHelp')}</p>
      <div className="rejilla-tres">
        <label>{t('year')}
          <select value={year} onChange={(e) => { setYear(e.target.value); setToDate(moveToYear(toDate, e.target.value)) }}>
            {years.map((y) => <option key={y} value={y}>{y}</option>)}
          </select>
        </label>
        <label>{t('toDate')}
          <DateField value={toDate} onChange={setToDate} company={company} label={t('toDate')} clearable monthHint={false}
                     baseDate={reportBase(toDate, year, workDate(company))} />
        </label>
        <div className="opciones-informe">
          <label className="opcion">
            <input type="checkbox" checked={hideZero} onChange={(e) => setHideZero(e.target.checked)} /> {t('hideZeroLines')}
          </label>
          <SimulationToggle value={sim} onChange={setSim} />
        </div>
      </div>
      <MonthPicker year={year} value={toDate} onChange={setToDate} />
      <SimulationBanner company={company} year={year} toDate={toDate} value={sim} />
      <ErrorBox error={error} company={company} />

      {statement === 'balance' && rows.length > 0 && (
        <div className={Math.abs(difference) < 0.005 ? 'cuadre ok' : 'cuadre descuadre'}>
          <span>{t('totalAssets')}: {m(amount('ACT'))}</span>
          <span>{t('totalEquityLiabilities')}: {m(amount('PNP'))}</span>
          <strong>{Math.abs(difference) < 0.005 ? `✓ ${t('balanced')}` : `${t('difference')}: ${m(difference)}`}</strong>
        </div>
      )}

      {/* En el móvil la tabla se desplaza en horizontal: con tabindex se puede mover también con el teclado */}
      <div className="tabla-ancha" tabIndex={0} role="region"
           aria-label={statement === 'balance' ? t('balanceSheet') : t('incomeStatement')}>
        <table className="estado">
          <thead>
            <tr>
              <th />
              <th className="num">{year}{toDate && <small>{t('fsAt').replace('{d}', shortDate(toDate))}</small>}</th>
              {hasPrev && <>
                <th className="num">{Number(year) - 1}
                  <small>{prevDate ? t('fsAt').replace('{d}', shortDate(prevDate)) : toDate ? t('fsClosing') : ''}</small>
                </th>
                <th className="num">{t('fsChange')}</th>
                <th className="num">%</th>
              </>}
            </tr>
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
                  {hasPrev && <>
                    <td className="num anterior">{m(r.amount_prev)}</td>
                    <td className="num variacion">{Math.abs(diff(r)) < 0.005 ? '' : m(diff(r))}</td>
                    <td className="num variacion">{pct(r)}</td>
                  </>}
                </tr>
                {open[r.code]?.map((a) => (
                  <tr key={`${r.code}-${a.account_no}`} className="cuenta-partida">
                    <td style={{ paddingLeft: `${28 + r.level * 14}px` }}>
                      <span className="codigo">{a.account_no}</span>
                      {language === 'en' ? a.account_name_en || a.account_name : a.account_name}
                    </td>
                    <td className="num">{m(a.amount)}</td>
                    {hasPrev && <>
                      <td className="num anterior">{m(a.amount_prev)}</td>
                      <td className="num variacion">{Math.abs(diff(a)) < 0.005 ? '' : m(diff(a))}</td>
                      <td className="num variacion">{pct(a)}</td>
                    </>}
                  </tr>
                ))}
                {open[r.code]?.length === 0 && (
                  <tr key={`${r.code}-vacio`} className="cuenta-partida"><td colSpan={hasPrev ? 5 : 2} className="ayuda">{t('noAccountsInLine')}</td></tr>
                )}
              </Fragment>
            ))}
          </tbody>
        </table>
      </div>
      {hasPrev && <p className="ayuda">{t(statement === 'balance' ? 'fsCompareBalance' : 'fsComparePyg')}</p>}
      <p className="ayuda">{t('statementsNote')}</p>
    </section>
  )
}