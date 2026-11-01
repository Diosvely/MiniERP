import { useState } from 'react'
import { useI18n } from '../i18n'
import { companyPath } from '../router'
import { fmtMetric, rankingRows, textOf } from '../dashboards'
import Link from './Link'

// TARJETA DE RANKING (v0.56.0 · ADR 0056): los clientes, proveedores o subgrupos de gasto con más importe, como barras
// horizontales. Cada fila lleva su importe y su % (nunca solo la barra), el año anterior debajo y, en clientes y
// proveedores, el enlace al libro mayor de su subcuenta. Las filas las decide la base de datos (erp.dash_ranking_card).
//   data: la respuesta de erp.dashboard_data · widget: la tarjeta (kind 'ranking', con widget.ranking)
export default function DashRanking({ company, data, widget }) {
  const { t, language } = useI18n()
  const [table, setTable] = useState(false)
  const r = widget.ranking
  const year = data.year, prevYear = Number(data.year) - 1
  const labels = {
    rest: (n) => t('dash.rank.rest').replace('{n}', n),
    none: t(`dash.rank.none.${r.source}`),
  }
  const rows = rankingRows(r, labels)
  const max = Math.max(1, ...rows.map((x) => Math.abs(Number(x.value))))
  const eur = (v) => fmtMetric(v, 'eur', language)
  const pct = (v) => fmtMetric(v, 'pct', language)
  const ledger = r.source !== 'expense_groups'
  const top = rows.filter((x) => x.kind === 'row')
  // concentración: cuánto suponen los primeros sobre el total (clientes y proveedores) · gastos: sobre las ventas
  const topShare = r.base === 'total' && Number(r.total.value) !== 0
    ? top.reduce((s, x) => s + Number(x.value), 0) / Number(r.total.value) : null
  const summary = r.base === 'total'
    ? (topShare != null ? t('dash.rank.top').replace('{n}', top.length).replace('{p}', pct(topShare)) : '')
    : (r.sales?.value ? t('dash.rank.onSales').replace('{p}', pct(Number(r.total.value) / Number(r.sales.value))) : '')
  const name = (x) => (ledger && x.kind === 'row'
    ? <Link to={companyPath(company.id, `reports/mayor/${x.key}/${year}`)} className="enlace">{x.label}</Link>
    : <>{x.label}{x.kind === 'row' && r.source === 'expense_groups' && <small className="rk-cuenta"> {x.key}</small>}</>)

  return (
    <>
      <div className="grafico-cabecera">
        <h3>{textOf(widget, 'label', language)}</h3>
        <button type="button" className="enlace" aria-pressed={table} onClick={() => setTable(!table)}>
          {table ? t('kpi.chartShow') : t('kpi.chartTable')}
        </button>
      </div>
      {summary && <p className="rk-resumen">{summary}</p>}
      {rows.length === 0 ? (
        <p className="ayuda" role="note">{t('dash.empty').replace('{y}', year)}</p>
      ) : table ? (
        <div className="tabla-ancha" tabIndex={0} role="region" aria-label={textOf(widget, 'label', language)}>
          <table className="informe">
            <thead>
              <tr><th>{t('dash.rank.name')}</th><th className="num">{year}</th>
                <th className="num">{r.base === 'sales' ? t('dash.rank.shareSales') : t('dash.rank.share')}</th>
                {data.has_prev && <th className="num">{prevYear}</th>}</tr>
            </thead>
            <tbody>
              {rows.map((x) => (
                <tr key={`${x.kind}${x.key ?? ''}`} className={x.kind === 'row' ? '' : 'rk-otra'}>
                  <td>{name(x)}</td>
                  <td className="num">{eur(x.value)}</td>
                  <td className="num">{x.share == null ? '—' : pct(x.share)}</td>
                  {data.has_prev && <td className="num anterior">{eur(x.prev)}</td>}
                </tr>
              ))}
              <tr className="total"><td>{t('dash.rank.total')}</td><td className="num">{eur(r.total.value)}</td><td />
                {data.has_prev && <td className="num anterior">{eur(r.total.prev)}</td>}</tr>
            </tbody>
          </table>
        </div>
      ) : (
        <ol className="rk-lista">
          {rows.map((x) => (
            <li key={`${x.kind}${x.key ?? ''}`} className={`rk-fila${x.kind === 'row' ? '' : ' rk-otra'}`}>
              <span className="rk-nombre">{name(x)}</span>
              <span className="rk-barra" aria-hidden="true">
                <i className={Number(x.value) < 0 ? 'negativa' : ''} style={{ width: `${(Math.abs(Number(x.value)) / max) * 100}%` }} />
              </span>
              <span className="rk-importe">
                <strong>{eur(x.value)}</strong>{x.share != null && <> · {pct(x.share)}</>}
                {data.has_prev && <small>{prevYear}: {eur(x.prev)}</small>}
              </span>
            </li>
          ))}
        </ol>
      )}
      {textOf(widget, 'help', language) && <p className="ayuda">{textOf(widget, 'help', language)}</p>}
    </>
  )
}
