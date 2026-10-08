import { Fragment, useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { money } from '../format'

// Estado de flujos de efectivo por los dos métodos (como el "Cash Flow Statement" de BC / SAP)
//   indirecto: el modelo normal del PGC (parte del resultado) · directo: cobros y pagos por su contrapartida (NIC 7)
// Abajo, el cuadre del auditor: efectivo inicial + flujos = efectivo final, y directo = indirecto
export default function CashFlow({ company }) {
  const { t, language } = useI18n()
  const [years, setYears] = useState([])
  const [year, setYear] = useState(new Date().getFullYear())
  const [method, setMethod] = useState('indirect')
  const [hideZero, setHideZero] = useState(true)
  const [rows, setRows] = useState([])
  const [check, setCheck] = useState(null)
  const [open, setOpen] = useState({})           // línea → cuentas que la forman (drill-down)
  const [loading, setLoading] = useState(false)
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
    setOpen({}); setLoading(true)
    supabase.rpc('cash_flow_statement', { p_company: company.id, p_year: Number(year), p_method: method })
      .then(({ data, error }) => {
        setLoading(false)
        if (error) return setError(error.message)
        setError(''); setRows(data)
      })
  }, [company.id, year, method])

  // El cuadre no depende del método: solo cambia con el año
  useEffect(() => {
    setCheck(null)
    supabase.rpc('cash_flow_check', { p_company: company.id, p_year: Number(year) })
      .then(({ data, error }) => (error ? setError(error.message) : setCheck(data)))
  }, [company.id, year])

  // Como en las cuentas anuales: las salidas de dinero entre paréntesis
  const m = (v) => (Number(v) < 0 ? `(${money(-v, language)})` : money(v, language))
  const label = (r) => (language === 'en' ? r.label_en : r.label)

  async function toggle(code) {
    if (open[code]) return setOpen({ ...open, [code]: null })
    const { data, error } = await supabase.rpc('cf_line_accounts', {
      p_company: company.id, p_year: Number(year), p_method: method, p_code: code,
    })
    if (error) return setError(error.message)
    setOpen({ ...open, [code]: data })
  }

  const visible = rows.filter((r) => !hideZero || r.is_total || Number(r.amount) !== 0 || Number(r.amount_prev) !== 0)
  const activities = ['A', 'B', 'C']
  const same = (a, b) => Math.abs(Number(a) - Number(b)) < 0.005

  return (
    <>
      <section className="tarjeta">
        <h2>{t('cashFlowTitle')}</h2>
        <p className="ayuda">{method === 'indirect' ? t('cashFlowIndirectHelp') : t('cashFlowDirectHelp')}</p>

        <div className="pestanas">
          {['indirect', 'direct'].map((x) => (
            <button key={x} type="button" className={method === x ? 'activa' : ''} onClick={() => setMethod(x)}>
              {t(`cashFlowMethod.${x}`)}
            </button>
          ))}
        </div>

        <div className="rejilla-tres">
          <label>{t('year')}
            <select value={year} onChange={(e) => setYear(e.target.value)}>
              {years.map((y) => <option key={y} value={y}>{y}</option>)}
            </select>
          </label>
          <label className="opcion">
            <input type="checkbox" checked={hideZero} onChange={(e) => setHideZero(e.target.checked)} /> {t('hideZeroLines')}
          </label>
        </div>
        {error && <p className="aviso">⚠ {error}</p>}

        {check && (
          <div className={check.balanced ? 'cuadre ok' : 'cuadre descuadre'}>
            <span>{t('cashOpening')}: {m(check.cash_opening)}</span>
            <span>+ {t('cashFlows')}: {m(check.cash_change)}</span>
            <span>= {t('cashClosing')}: {m(check.cash_closing)}</span>
            <strong>{check.balanced ? `✓ ${t('cashFlowBalanced')}` : `⚠ ${t('cashFlowUnbalanced')}`}</strong>
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
        {loading && <p className="ayuda">{t('cashFlowLoading')}…</p>}
        <p className="ayuda">{t('cashFlowNote')}</p>
      </section>

      {check && (
        <section className="tarjeta">
          <h2>{t('cashFlowCompare')}</h2>
          <p className="ayuda">{t('cashFlowCompareHelp')}</p>
          <div className="tabla-ancha">
            <table className="informe">
              <thead>
                <tr>
                  <th>{t('cashFlowActivity')}</th>
                  <th className="num">{t('cashFlowMethod.indirect')}</th>
                  <th className="num">{t('cashFlowMethod.direct')}</th>
                  <th className="num">{t('difference')}</th>
                </tr>
              </thead>
              <tbody>
                {activities.map((a) => {
                  const diff = Number(check.indirect[a]) - Number(check.direct[a])
                  return (
                    <tr key={a}>
                      <td>{t(`cashFlowActivityName.${a}`)}</td>
                      <td className="num">{m(check.indirect[a])}</td>
                      <td className="num">{m(check.direct[a])}</td>
                      <td className={`num ${same(diff, 0) ? '' : 'reduce'}`}>{same(diff, 0) ? '—' : m(diff)}</td>
                    </tr>
                  )
                })}
                <tr className="total">
                  <td><strong>{t('cashFlowTotal')}</strong></td>
                  <td className="num"><strong>{m(check.indirect.total)}</strong></td>
                  <td className="num"><strong>{m(check.direct.total)}</strong></td>
                  <td className="num"><strong>{same(check.indirect.total, check.direct.total) ? '✓' : m(check.indirect.total - check.direct.total)}</strong></td>
                </tr>
              </tbody>
            </table>
          </div>

          {check.cross_count === 0 ? (
            <p className="exito">✓ {t('cashFlowNoCross')}</p>
          ) : (
            <>
              <h3>{t('cashFlowCrossTitle').replace('{n}', check.cross_count)}</h3>
              <p className="ayuda">{t('cashFlowCrossHelp')}</p>
              <div className="tabla-ancha">
                <table className="informe">
                  <thead>
                    <tr>
                      <th>{t('entry')}</th><th>{t('date')}</th><th>{t('description')}</th>
                      {activities.map((a) => <th key={a} className="num">{a}</th>)}
                    </tr>
                  </thead>
                  <tbody>
                    {check.cross_entries.map((c) => (
                      <tr key={c.entry_no}>
                        <td>{c.entry_no}</td>
                        <td>{c.date}</td>
                        <td>{c.description}</td>
                        {activities.map((a) => <td key={a} className="num">{c.activities[a] != null ? m(c.activities[a]) : ''}</td>)}
                      </tr>
                    ))}
                    <tr className="total">
                      <td colSpan={3}><strong>{t('cashFlowCrossExplains')}</strong></td>
                      {activities.map((a) => <td key={a} className="num"><strong>{m(check.cross_total[a])}</strong></td>)}
                    </tr>
                  </tbody>
                </table>
              </div>
              {check.cross_count > check.cross_entries.length && (
                <p className="ayuda">{t('cashFlowCrossMore').replace('{n}', check.cross_count - check.cross_entries.length)}</p>
              )}
            </>
          )}
        </section>
      )}
    </>
  )
}
