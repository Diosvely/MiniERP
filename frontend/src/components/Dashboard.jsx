import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { workDate, workYear } from '../workDate'
import { companyPath } from '../router'
import { change, fmtMetric, seriesRows, textOf, zoneStatus } from '../dashboards'
import { monthNames, moveToYear, reportBase, simTitle } from '../reportPeriod'
import { downloadXlsx, fileName } from '../exportXlsx'
import DateField from './DateField'
import MonthPicker from './MonthPicker'
import SimulationToggle, { SimulationBanner } from './SimulationToggle'
import ReportActions from './ReportActions'
import ErrorBox from './ErrorBox'
import Loading from './Loading'
import Link from './Link'
import DashChart from './DashChart'

// UN TABLERO (v0.52.0 · ADR 0052): la web dibuja lo que dice el catálogo de la base de datos (0075). Una sola llamada,
// erp.dashboard_data, trae cada cifra con el año anterior a la misma fecha y las series de cada fin de mes, calculadas
// con las mismas reglas que el Balance y la PyG (cuadran al céntimo). Filtros como los informes (v0.51.0): ejercicio,
// «hasta» con la fecha rápida y los meses, y la simulación con los asientos en edición.
//   code: el tablero (de la dirección #/empresa/<id>/tableros/<código>)
const BADGE = { ok: '✓', low: '▼', high: '▲' }

export default function Dashboard({ company, code }) {
  const { t, language } = useI18n()
  const [years, setYears] = useState([])
  const [year, setYear] = useState(() => workYear(company))
  const [toDate, setToDate] = useState('')
  const [sim, setSim] = useState(false)
  const [data, setData] = useState(null)
  const [error, setError] = useState('')

  useEffect(() => {
    supabase.from('fiscal_years').select('year').eq('company_id', company.id).order('year')
      .then(({ data, error }) => {
        if (error) return setError(error.message)
        setYears(data.map((r) => r.year))
        if (data.length && !data.some((r) => r.year === Number(year))) setYear(data[data.length - 1].year)
      })
  }, [company.id])   // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    let alive = true
    supabase.rpc('dashboard_data', { p_company: company.id, p_dashboard: code, p_year: Number(year), p_to_date: toDate || null, p_drafts: sim })
      .then(({ data, error }) => {
        if (!alive) return
        if (error) { setError(error.message); setData(null) } else { setError(''); setData(data) }
      })
    return () => { alive = false }
  }, [company.id, code, year, toDate, sim])

  const short = (d) => (d ? d.split('-').reverse().join('/') : '')
  const title = data ? textOf(data, 'label', language) : t('dash.title')
  const filters = `${t('year')} ${year} · ${t('dash.at').replace('{d}', short(data?.to))}`

  // Excel: las cifras y, debajo, cada gráfico mes a mes; siempre el ejercicio y el anterior (números, no texto)
  function exportExcel() {
    const names = monthNames(language)
    const rows = []
    for (const w of data.widgets) {
      rows.push({ a: textOf(w, 'label', language).toUpperCase() })
      if (w.kind === 'bars' || w.kind === 'lines') {
        for (const it of w.items) {
          for (const r of seriesRows(data, w)) {
            rows.push({ a: `${textOf(it, 'label', language)} · ${names[Number(r.month.slice(5, 7)) - 1]}`,
              b: r[it.code] == null ? null : Number(r[it.code]), c: r[`${it.code}_prev`] == null ? null : Number(r[`${it.code}_prev`]) })
          }
        }
      } else {
        for (const it of w.items) {
          // los porcentajes, en % (53,56); los ratios, en veces (4,17)
          const num = (v) => (v == null ? null : it.unit === 'pct' ? Math.round(Number(v) * 10000) / 100 : Number(v))
          rows.push({ a: `${textOf(it, 'label', language)}${it.unit === 'pct' ? ' (%)' : ''}`, b: num(it.value), c: num(it.prev) })
        }
      }
    }
    return downloadXlsx({
      title: `${simTitle(title, sim, t('sim.prefix'))} · ${company.name ?? ''}`, subtitle: filters, sheet: t('dash.title'),
      file: fileName(simTitle(title, sim, t('sim.prefix')), company.name, year, toDate),
      columns: [
        { header: '', key: 'a', type: 'text', width: 40 },
        { header: `${year}`, key: 'b', type: 'money' }, { header: `${Number(year) - 1}`, key: 'c', type: 'money' },
      ],
      rows,
    })
  }

  return (
    <>
      <section className="tarjeta tablero-filtros">
        <div className="titulo-informe">
          <h2>{title}</h2>
          {data && <ReportActions onExcel={exportExcel} info={`${sim ? `${t('sim.prefix')} · ` : ''}${company.name ?? ''} · ${filters}`} />}
        </div>
        {data && textOf(data, 'description', language) && <p className="ayuda">{textOf(data, 'description', language)}</p>}
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
          <SimulationToggle value={sim} onChange={setSim} />
        </div>
        <MonthPicker year={year} value={toDate} onChange={setToDate} />
        <SimulationBanner company={company} year={year} toDate={toDate} value={sim} />
        <ErrorBox error={error} company={company} />
        {data && <p className="ayuda">{data.has_prev
          ? t('dash.compare').replace('{d}', short(data.to)).replace('{p}', short(data.prev_to))
          : t('dash.noPrev').replace('{d}', short(data.to))}</p>}
      </section>

      {!data && !error && <Loading />}
      {data && (
        <div className="tablero">
          {data.widgets.map((w) => (
            <section key={w.sort} className={`tarjeta tablero-tarjeta ${w.size === 'half' ? 'media' : 'entera'}`}>
              {w.kind === 'kpis' && <Kpis company={company} data={data} widget={w} />}
              {(w.kind === 'bars' || w.kind === 'lines') && <DashChart data={data} widget={w} />}
              {w.kind === 'table' && <Health company={company} data={data} widget={w} />}
            </section>
          ))}
        </div>
      )}
    </>
  )
}

// Cifras clave: valor, año anterior a la misma fecha, variación (▲ ▼ y %, nunca solo color) y el informe que la explica
function Kpis({ company, data, widget }) {
  const { t, language } = useI18n()
  const locale = language === 'en' ? 'en-GB' : 'es-ES'
  return (
    <>
      <h3 className="oculto">{textOf(widget, 'label', language)}</h3>
      <div className="tablero-cifras">
        {widget.items.map((it) => {
          const c = change(it.value, it.prev)
          return (
            <div key={it.code} className="cifra">
              <span className="cifra-titulo">{textOf(it, 'label', language)}</span>
              <strong className="cifra-valor">{fmtMetric(it.value, it.unit, language)}</strong>
              {c && (
                <span className={`cifra-variacion ${c.dir}`}>
                  {c.dir === 'up' ? '▲' : c.dir === 'down' ? '▼' : '='} {fmtMetric(Math.abs(c.diff), it.unit, language)}
                  {c.pct != null && ` (${c.pct > 0 ? '+' : c.pct < 0 ? '−' : ''}${Math.abs(c.pct * 100).toLocaleString(locale, { maximumFractionDigits: 1 })} %)`}
                  <small> · {Number(data.year) - 1}: {fmtMetric(it.prev, it.unit, language)}</small>
                </span>
              )}
              {it.link && <Link to={companyPath(company.id, it.link)} className="enlace">{t(`dash.link.${it.link}`)}</Link>}
            </div>
          )
        })}
      </div>
    </>
  )
}

// Salud financiera: los ratios con la zona de referencia de la pantalla Ratios
function Health({ company, data, widget }) {
  const { t, language } = useI18n()
  const zone = (it) => {
    const f = (v) => fmtMetric(v, it.unit, language)
    if (it.ref_min != null && it.ref_max != null) return `${f(it.ref_min)} – ${f(it.ref_max)}`
    if (it.ref_min != null) return `≥ ${f(it.ref_min)}`
    if (it.ref_max != null) return `≤ ${f(it.ref_max)}`
    return '—'
  }
  return (
    <>
      <div className="grafico-cabecera">
        <h3>{textOf(widget, 'label', language)}</h3>
        <Link to={companyPath(company.id, 'ratios')} className="enlace">{t('dash.link.ratios')}</Link>
      </div>
      <div className="tabla-ancha" tabIndex={0} role="region" aria-label={textOf(widget, 'label', language)}>
        <table className="informe tablero-salud">
          <thead>
            <tr><th /><th className="num">{data.year}</th>{data.has_prev && <th className="num">{Number(data.year) - 1}</th>}
              <th className="num">{t('dash.zone')}</th></tr>
          </thead>
          <tbody>
            {widget.items.map((it) => {
              const st = zoneStatus(it.value, it.ref_min, it.ref_max)
              return (
                <tr key={it.code}>
                  <td>{textOf(it, 'label', language)}{textOf(it, 'help', language) && <small className="ayuda">{textOf(it, 'help', language)}</small>}</td>
                  <td className="num">
                    {fmtMetric(it.value, it.unit, language)}
                    {st && <span className={`ratio-estado ${st}`} title={t(`ratioStatus.${st}`)}> {BADGE[st]} <span className="oculto">{t(`ratioStatus.${st}`)}</span></span>}
                  </td>
                  {data.has_prev && <td className="num anterior">{fmtMetric(it.prev, it.unit, language)}</td>}
                  <td className="num">{zone(it)}</td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>
      {textOf(widget, 'help', language) && <p className="ayuda">{textOf(widget, 'help', language)}</p>}
    </>
  )
}
