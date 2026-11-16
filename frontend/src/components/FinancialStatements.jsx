import { Fragment, useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { workDate, workYear } from '../workDate'
import { money } from '../format'
import { COMP_RATIOS, COMPARE_WITH, changePct, prevCutoff, timesBigger } from '../compare'
import ErrorBox from './ErrorBox'
import ReportActions from './ReportActions'
import { downloadXlsx, fileName } from '../exportXlsx'
import DateField from './DateField'
import MonthPicker from './MonthPicker'
import SimulationToggle, { SimulationBanner } from './SimulationToggle'
import { moveToYear, reportBase, simTitle } from '../reportPeriod'
import { accountSubLine, anomalyByAccount, anomalyCounts } from '../anomalies'
import { companyPath } from '../router'
import Link from './Link'
import Sources from './Sources'
import { BALANCE_MODELS, modelFor, modelSource, readModel, saveModel } from '../balanceModels'

// Balance de situación y Cuenta de Pérdidas y Ganancias (modelo PYMES del PGC)
//   statement: 'balance' | 'pyg' · columnas ejercicio actual y anterior, como en las cuentas anuales
// v0.30.0 · ANÁLISIS HORIZONTAL: variación en importe y en % frente al ejercicio anterior, y el anterior también al
// desplegar una partida. Con fecha de corte (0032): la PyG se compara con el mismo periodo del año anterior y el
// Balance con el cierre del ejercicio anterior (NIC 34). La variación no lleva color: que suba un gasto o un ingreso
// no es "bueno" o "malo" por sí solo; el signo y el % bastan para ver dónde mirar.
// v0.51.0 · «hasta» con la fecha rápida y los botones de mes, y la simulación con los asientos en edición (ADR 0051).
// v0.57.0 · SALDOS AL REVÉS (ADR 0057): el ERP no compensa; en el Balance avisa con una franja, un ⚠ en cada partida
// que contiene alguna cuenta al revés y, al desplegarla, el ⚠ y la nota de la cuenta (erp.fs_line_anomalies).
// v0.60.0 · MODELOS (ADR 0062): el Balance en el modelo PYMES (por defecto), abreviado o normal del PGC. Es el mismo
// balance: las mismas cuentas con el mismo saldo, recolocadas en las partidas de cada modelo. La PyG, solo en PYMES.
// v0.60.7 · BALANCE COMPENSADO (ADR 0064): «Comparar con» el ejercicio anterior (por defecto, lo de siempre) o con el
// Balance que saldría compensando las subcuentas de un mismo subgrupo (erp.fs_compensated): sin compensar ·
// compensado · diferencia · %, un aviso con lo que esconde y los ratios de los dos (erp.fs_compensated_ratios). El ERP
// sigue sin compensar: la columna compensada solo enseña cuánto engañaría.
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
  const [anomalies, setAnomalies] = useState([])  // v0.57.0: cuentas con saldo al revés y su partida
  const [chosen, setChosen] = useState(readModel)  // v0.60.0: modelo del Balance (se recuerda en el navegador)
  const model = modelFor(statement, chosen)
  const [compare, setCompare] = useState('prev')   // v0.60.7: 'prev' (ejercicio anterior) o 'comp' (compensado)
  const comp = statement === 'balance' && compare === 'comp'
  const [ratios, setRatios] = useState([])
  const chooseModel = (code) => { setChosen(code); saveModel(code) }

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
    if (comp) {
      const args = { p_company: company.id, p_year: Number(year), p_to_date: toDate || null, p_drafts: sim, p_model: model }
      // La columna «anterior» pasa a ser la compensada: así sirven la tabla, la variación y el Excel de siempre
      supabase.rpc('fs_compensated', args)
        .then(({ data, error }) => (error ? setError(error.message)
          : (setError(''), setRows((data ?? []).map((r) => ({ ...r, amount_prev: r.amount_comp }))))))
      supabase.rpc('fs_compensated_ratios', args).then(({ data, error }) => setRatios(error ? [] : data ?? []))
    } else {
      supabase.rpc('financial_statement', {
        p_company: company.id, p_year: Number(year), p_statement: statement, p_to_date: toDate || null, p_drafts: sim,
        p_model: model,
      }).then(({ data, error }) => (error ? setError(error.message) : (setError(''), setRows(data))))
    }
    if (statement !== 'balance') return   // solo el Balance lleva el aviso (abajo, «shown»)
    supabase.rpc('fs_line_anomalies', {
      p_company: company.id, p_year: Number(year), p_to: toDate || null, p_drafts: sim, p_model: model,
    })
      .then(({ data, error }) => setAnomalies(error ? [] : data ?? []))   // el aviso no debe impedir ver el Balance
  }, [company.id, year, toDate, statement, sim, model, comp])

  // Las cuentas anuales muestran los negativos entre paréntesis: (1.234,00)
  const m = (v) => (Number(v) < 0 ? `(${money(-v, language)})` : money(v, language))
  const label = (r) => (language === 'en' ? r.label_en : r.label)

  // ¿Hay ejercicio anterior? Si no, no se enseñan sus columnas (estarían a cero y confundirían)
  const hasPrev = comp || years.includes(Number(year) - 1)
  // Fecha de corte del ejercicio anterior: Balance → su cierre (null); PyG → la misma fecha un año antes
  const prevDate = prevCutoff(statement, toDate)
  const shortDate = (d) => new Date(`${d}T00:00:00`).toLocaleDateString(language === 'en' ? 'en-GB' : 'es-ES')

  async function toggle(code) {
    if (open[code]) return setOpen({ ...open, [code]: null })
    const ask = (y, d) => supabase.rpc('fs_line_accounts', {
      p_company: company.id, p_year: y, p_statement: statement, p_code: code, p_to_date: d, p_drafts: sim, p_model: model,
    })
    // Compensado: las cuentas, con su saldo sin compensar (compensar es sumar cuentas: no hay importe por cuenta)
    const [now, before] = await Promise.all([ask(Number(year), toDate || null),
      hasPrev && !comp ? ask(Number(year) - 1, prevDate) : Promise.resolve({ data: [] })])
    if (now.error || before.error) return setError((now.error || before.error).message)
    // Una fila por subcuenta con los dos importes (puede existir solo en uno de los dos ejercicios)
    const byAccount = new Map()
    for (const a of now.data) byAccount.set(a.account_no, { ...a, amount_prev: comp ? null : 0 })
    for (const a of before.data) {
      const row = byAccount.get(a.account_no)
      if (row) row.amount_prev = a.amount
      else byAccount.set(a.account_no, { ...a, amount: 0, amount_prev: a.amount })
    }
    setOpen({ ...open, [code]: [...byAccount.values()].sort((a, b) => a.account_no.localeCompare(b.account_no)) })
  }

  // Variación: importe y % sobre el valor absoluto del anterior (si el anterior es 0, el % no tiene sentido)
  //   compensado: sin compensar − compensado (lo que la compensación esconde) y su % sobre el compensado
  const diff = (r) => (r.amount_prev == null ? 0 : Number(r.amount) - Number(r.amount_prev))
  const pct = (r) => (r.amount_prev == null ? '' : changePct(r.amount, r.amount_prev, language))
  const colPrev = comp ? t('cmp.comp') : String(Number(year) - 1)
  const colChange = comp ? t('cmp.diff') : t('fsChange')

  // Excel: las partidas visibles con su sangría, los dos ejercicios y la variación (números, no texto)
  const title = simTitle(statement === 'balance' ? t('balanceSheet') : t('incomeStatement'), sim, t('sim.prefix'))
  const modelName = statement === 'balance' ? ` · ${t('fsModel.label')} ${t(`fsModel.${model}`)}${comp ? ` · ${t('cmp.title')}` : ''}` : ''
  const filters = `${t('year')} ${year}${toDate ? ` · ${t('fsAt').replace('{d}', shortDate(toDate))}` : ''}${modelName}`
  const exportExcel = () => downloadXlsx({
    title: `${title} · ${company.name ?? ''}`, subtitle: filters, sheet: title,
    file: fileName(title, company.name, year, toDate),
    columns: [
      { header: t('fsLine'), key: 'label', type: 'text', width: 60 },
      { header: comp ? `${year} · ${t('cmp.uncomp')}` : String(year), key: 'amount', type: 'money' },
      ...(hasPrev ? [
        { header: colPrev, key: 'amount_prev', type: 'money' },
        { header: colChange, key: 'change', type: 'money' },
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
  const shown = statement === 'balance' ? anomalies : []
  const marks = anomalyCounts(rows, shown)
  const byAccount = anomalyByAccount(shown)
  const errors = shown.filter((a) => a.severity === 'error').length
  const visible = rows.filter((r) => !hideZero || r.is_total || Number(r.amount) !== 0 || Number(r.amount_prev) !== 0)

  return (
    <section className="tarjeta">
      <div className="titulo-informe">
        <h2>{statement === 'balance' ? t('balanceSheet') : t('incomeStatement')}</h2>
        {rows.length > 0 && <ReportActions onExcel={exportExcel} info={`${sim ? `${t('sim.prefix')} · ` : ''}${company.name} · ${filters}`} />}
      </div>
      {statement === 'balance' && (
        <div className="modelo-balance">
          <div className="pestanas-modelo" role="radiogroup" aria-label={t('fsModel.label')}>
            <span>{t('fsModel.label')}</span>
            {BALANCE_MODELS.map(({ code }) => (
              <button key={code} type="button" role="radio" aria-checked={model === code}
                      className={model === code ? 'activa' : 'secundario'} onClick={() => chooseModel(code)}>
                {t(`fsModel.${code}`)}
              </button>
            ))}
          </div>
          <p className="ayuda norma-modelo">{t(`fsModel.norm.${model}`)} <Sources ids={[modelSource(model)]} /></p>
          <div className="pestanas-modelo" role="radiogroup" aria-label={t('cmp.label')}>
            <span>{t('cmp.label')}</span>
            {COMPARE_WITH.map((c) => (
              <button key={c} type="button" role="radio" aria-checked={compare === c}
                      className={compare === c ? 'activa' : 'secundario'} onClick={() => setCompare(c)}>
                {t(`cmp.${c}`)}
              </button>
            ))}
          </div>
        </div>
      )}
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

      {comp && rows.length > 0 && <Compensated ratios={ratios} />}

      {shown.length > 0 && (
        <p className="aviso-reves" role="note">
          ⚠ {t(shown.length === 1 ? 'reverse.one' : 'reverse.many').replace('{n}', shown.length)}
          {errors > 0 && <strong> {t('reverse.errors').replace('{n}', errors)}</strong>}
          {' '}{t('reverse.why')}{' '}
          <Link to={companyPath(company.id, 'checks')} className="enlace">{t('reverse.go')}</Link>
        </p>
      )}

      {/* En el móvil la tabla se desplaza en horizontal: con tabindex se puede mover también con el teclado */}
      <div className="tabla-ancha" tabIndex={0} role="region"
           aria-label={statement === 'balance' ? t('balanceSheet') : t('incomeStatement')}>
        <table className="estado">
          <thead>
            <tr>
              <th />
              <th className="num">{year}{toDate && <small>{t('fsAt').replace('{d}', shortDate(toDate))}</small>}
                {comp && <small>{t('cmp.uncomp')}</small>}</th>
              {hasPrev && <>
                <th className="num">{colPrev}
                  {!comp && <small>{prevDate ? t('fsAt').replace('{d}', shortDate(prevDate)) : toDate ? t('fsClosing') : ''}</small>}
                </th>
                <th className="num">{colChange}</th>
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
                    {marks[r.code] && (
                      <span className={`marca-reves${marks[r.code].errors ? ' error' : ''}`}
                            title={t('reverse.line').replace('{n}', marks[r.code].n)}>
                        {' '}⚠ {marks[r.code].n}<span className="oculto"> {t('reverse.line').replace('{n}', marks[r.code].n)}</span>
                      </span>
                    )}
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
                      {accountSubLine(a, r.code, rows) && (
                        <small className="sublinea"> → {label(accountSubLine(a, r.code, rows))}</small>
                      )}
                      {byAccount.get(a.account_no) && (
                        <small className={`nota-reves${byAccount.get(a.account_no).severity === 'error' ? ' error' : ''}`}>
                          ⚠ {t(byAccount.get(a.account_no).severity === 'error' ? 'reverse.accountError' : 'reverse.account')}
                          {' '}{language === 'en' ? byAccount.get(a.account_no).note_en || byAccount.get(a.account_no).note : byAccount.get(a.account_no).note}
                        </small>
                      )}
                    </td>
                    <td className="num">{m(a.amount)}</td>
                    {hasPrev && <>
                      <td className="num anterior">{a.amount_prev == null ? '' : m(a.amount_prev)}</td>
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
      {hasPrev && <p className="ayuda">{comp ? t('cmp.help') : t(statement === 'balance' ? 'fsCompareBalance' : 'fsComparePyg')}</p>}
      <p className="ayuda">{t('statementsNote')}</p>
    </section>
  )
}
// v0.60.7 · Lo que esconde la compensación y los ratios de los dos Balances (erp.fs_compensated_ratios)
function Compensated({ ratios }) {
  const { t, language } = useI18n()
  const get = (code) => ratios.find((r) => r.code === code)
  const hidden = Number(get('HIDDEN')?.amount ?? 0)
  const locale = language === 'en' ? 'en-GB' : 'es-ES'
  const fmt = (code, v) => (v == null ? '—' : code === 'DEBT'
    ? `${(Number(v) * 100).toLocaleString(locale, { minimumFractionDigits: 1, maximumFractionDigits: 1 })} %`
    : Number(v).toLocaleString(locale, { minimumFractionDigits: 2, maximumFractionDigits: 2 }))
  return (
    <>
      <p className={`aviso-compensado${hidden >= 0.005 ? '' : ' ok'}`} role="note">
        {hidden >= 0.005
          ? t('cmp.hidden').replace('{x}', money(hidden, language))
          : t('cmp.nothing')}
      </p>
      <div className="ratios-compensado">
        {COMP_RATIOS.map((code) => {
          const r = get(code)
          const k = timesBigger(r?.amount, r?.amount_comp)
          return (
            <div key={code} className="ratio-compensado">
              <strong>{t(`cmp.ratio.${code}`)}</strong>
              <span className="ratio-sin">{fmt(code, r?.amount)} <small>{t('cmp.uncomp')}</small></span>
              <span className="ratio-con">{fmt(code, r?.amount_comp)} <small>{t('cmp.compShort')}</small></span>
              {k != null && Math.abs(k - 1) >= 0.05 && (
                <small className="ratio-veces">{t(k > 1 ? 'cmp.bigger' : 'cmp.smaller')
                  .replace('{k}', (k > 1 ? k : 1 / k).toLocaleString(locale, { maximumFractionDigits: 1 }))}</small>
              )}
            </div>
          )
        })}
      </div>
    </>
  )
}
