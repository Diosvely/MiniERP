import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { money } from '../format'
import { workYear } from '../workDate'
import { partA, partB, paren } from '../grants'
import { downloadXlsx, fileName } from '../exportXlsx'
import Sources from './Sources'
import ErrorBox from './ErrorBox'
import ReportActions from './ReportActions'

// ESTADO DE CAMBIOS EN EL PATRIMONIO NETO (v0.44.0; PGC, 3.ª parte): parte A, ingresos y gastos reconocidos (el
// resultado + lo imputado directamente al patrimonio neto − lo transferido a resultados), y parte B, el estado total
// por columnas, del saldo inicial al final, comprobado contra el patrimonio neto del balance. Lo calcula la base de
// datos (erp.equity_statement, 0065); para todas las empresas (el PGC de pymes no exige la parte A, pero se enseña).
export default function EquityStatement({ company }) {
  const { t, language } = useI18n()
  const [years, setYears] = useState([])
  const [year, setYear] = useState(() => workYear(company))
  const [data, setData] = useState(null)
  const [error, setError] = useState('')
  const m = (v) => paren(v, (x) => money(x, language))

  useEffect(() => {
    supabase.from('fiscal_years').select('year').eq('company_id', company.id).order('year')
      .then(({ data: d, error: e }) => {
        if (e) return setError(e.message)
        setYears(d.map((r) => r.year))
        if (d.length && !d.some((r) => r.year === Number(year))) setYear(d[d.length - 1].year)
      })
  }, [company.id])   // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    let alive = true
    supabase.rpc('equity_statement', { p_company: company.id, p_year: Number(year) }).then(({ data: d, error: e }) => {
      if (!alive) return
      if (e) { setData(null); return setError(e.code === 'PGRST202' ? t('ecpn.dbMissing') : e.message) }
      setError(''); setData(d)
    })
    return () => { alive = false }
  }, [company.id, year])   // eslint-disable-line react-hooks/exhaustive-deps

  const a = data ? partA(data.part_a) : []
  const b = data ? partB(data) : { cols: [], rows: [] }
  const exportExcel = () => downloadXlsx({
    title: `${t('ecpn.title')} · ${company.name ?? ''}`, subtitle: `${t('year')} ${year}`, sheet: 'ECPN',
    file: fileName('ECPN', company.name, year),
    columns: [{ header: t('ecpn.concept'), key: 'label', type: 'text', width: 60 }, ...b.cols.map((c) => ({ header: t(`ecpn.col.${c}`), key: c, type: 'money' })),
      { header: t('ecpn.col.total'), key: 'total', type: 'money' }],
    rows: [
      ...a.map((r) => ({ label: `A · ${t(`ecpn.a.${r.key}`)}`, total: r.amount })),
      {},
      ...b.rows.map((r) => ({ label: `B · ${t(`ecpn.row.${r.key}`)}`, ...r.values, total: r.total })),
    ],
  })

  return (
    <>
      <section className="tarjeta">
        <div className="titulo-modelo"><h2>{t('ecpn.title')}</h2><Sources ids={['pgc']} /></div>
        <p className="ayuda">{t('ecpn.intro')}</p>
        <div className="rejilla-tres">
          <label>{t('year')}
            <select value={year} onChange={(e) => setYear(Number(e.target.value))}>
              {years.map((y) => <option key={y} value={y}>{y}</option>)}
            </select>
          </label>
        </div>
        <ErrorBox error={error} company={company} />
        {data && <ReportActions onExcel={exportExcel} info={`${company.name ?? ''} · ${t('year')} ${year}`} />}
      </section>

      {data && (
        <section className="tarjeta">
          <h3>{t('ecpn.partA')}</h3>
          <p className="ayuda">{t('ecpn.partAHelp')}</p>
          <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('ecpn.partA')}>
            <table className="informe">
              <thead><tr><th scope="col">{t('ecpn.concept')}</th><th scope="col" className="num">{year}</th></tr></thead>
              <tbody>{a.map((r) => (
                <tr key={r.key} className={r.level === 0 ? 'total' : ''}>
                  <td style={{ paddingLeft: r.level ? '1.5rem' : undefined }}>{t(`ecpn.a.${r.key}`)}</td><td className="num">{m(r.amount)}</td>
                </tr>))}</tbody>
            </table>
          </div>
        </section>
      )}

      {data && (
        <section className="tarjeta">
          <h3>{t('ecpn.partB')}</h3>
          <p className="ayuda">{t('ecpn.partBHelp')}</p>
          <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('ecpn.partB')}>
            <table className="informe">
              <thead><tr><th scope="col">{t('ecpn.concept')}</th>{b.cols.map((c) => <th key={c} scope="col" className="num">{t(`ecpn.col.${c}`)}</th>)}
                <th scope="col" className="num">{t('ecpn.col.total')}</th></tr></thead>
              <tbody>{b.rows.map((r) => (
                <tr key={r.key} className={['start', 'end'].includes(r.key) ? 'total' : ''}>
                  <td>{t(`ecpn.row.${r.key}`).replace('{y}', year)}</td>
                  {b.cols.map((c) => <td key={c} className="num">{r.values[c] ? m(r.values[c]) : '—'}</td>)}
                  <td className="num">{m(r.total)}</td>
                </tr>))}</tbody>
            </table>
          </div>
          <p className={data.ok ? 'exito' : 'aviso'} role="status">
            {data.ok ? '✓ ' : '⚠ '}{t(data.ok ? 'ecpn.ok' : 'ecpn.notOk').replace('{m}', money(data.balance_net_worth, language)).replace('{e}', money(data.end, language))}
          </p>
        </section>
      )}
    </>
  )
}
