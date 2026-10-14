import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { money } from '../format'
import { workDate } from '../workDate'
import { AGING_BUCKETS, agingTotals, difference, unmatched } from '../payments'
import { downloadXlsx, fileName } from '../exportXlsx'
import ReportActions from './ReportActions'
import Empty from './Empty'
import ErrorBox from './ErrorBox'

// ANTIGÜEDAD DE SALDOS (aging) a una fecha: lo pendiente de cada tercero por tramos de días vencidos, como el
// "Aged Accounts Payable / Receivable" de Business Central o el S_ALR_87012078 / 87012168 de SAP.
// Al lado, el SALDO CONTABLE de su subcuenta: si no coincide con las facturas pendientes, hay movimientos sin
// vincular (pagos hechos a mano, saldos importados…). Es el control "después" de los ERP españoles.
export default function Aging({ company, onPay }) {
  const { t, language } = useI18n()
  const [type, setType] = useState('purchase')
  const [date, setDate] = useState(workDate(company))
  const [rows, setRows] = useState([])
  const [error, setError] = useState('')

  useEffect(() => {
    let alive = true
    supabase.rpc('aging', { p_company: company.id, p_type: type, p_date: date || null }).then(({ data, error }) => {
      if (!alive) return
      if (error) setError(error.message)
      else { setError(''); setRows(data ?? []) }
    })
    return () => { alive = false }
  }, [company.id, type, date])

  const m = (v) => (Number(v) ? money(v, language) : '')
  const tot = agingTotals(rows)
  const cols = [...AGING_BUCKETS, 'total']
  const title = t(`aging.title.${type}`)

  return (
    <section className="tarjeta antiguedad">
      <div className="grafico-cabecera">
        <h2>{title}</h2>
      </div>
      <p className="ayuda">{t('aging.intro')}</p>
      <div className="rejilla-cabecera">
        <label>{t('aging.of')}
          <select value={type} onChange={(e) => setType(e.target.value)}>
            <option value="purchase">{t('aging.purchase')}</option>
            <option value="sale">{t('aging.sale')}</option>
          </select>
        </label>
        <label>{t('aging.date')}<input type="date" value={date} onChange={(e) => setDate(e.target.value)} /></label>
      </div>
      <ErrorBox error={error} company={company} />

      {rows.length === 0 ? <Empty icon="✅" text={t(`aging.empty.${type}`)} /> : (
        <>
          <ReportActions info={`${company.name} · ${title} · ${date}`}
            onExcel={() => downloadXlsx({
              title: `${title} · ${company.name}`, subtitle: `${t('aging.date')} ${date}`, sheet: t('aging.sheet'),
              file: fileName(title, company.name, date),
              columns: [
                { header: t('account'), key: 'partner_account_no', type: 'text', width: 12 },
                { header: t('aging.partner'), key: 'partner_name', type: 'text', width: 32 },
                ...cols.map((c) => ({ header: t(`aging.col.${c}`), key: c, type: 'money' })),
                { header: t('aging.col.account_balance'), key: 'account_balance', type: 'money' },
                { header: t('aging.col.difference'), key: 'difference', type: 'money' },
              ],
              rows: rows.map((r) => ({ ...r, difference: difference(r) })),
            })} />
          <div className="tabla-ancha" tabIndex={0}>
            <table className="informe">
              <thead>
                <tr>
                  <th>{t('aging.partner')}</th>
                  {cols.map((c) => <th key={c} className="num">{t(`aging.col.${c}`)}</th>)}
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.partner_id}>
                    <td>
                      <span className="codigo">{r.partner_account_no}</span>{' '}
                      {onPay && Number(r.total) > 0
                        ? <button type="button" className="enlace" onClick={() => onPay(type, r.partner_id)}>{r.partner_name}</button>
                        : r.partner_name}
                      {r.open_invoices > 0 && <span className="ayuda"> · {t('aging.invoices').replace('{n}', r.open_invoices)}</span>}
                    </td>
                    {AGING_BUCKETS.map((c) => (
                      <td key={c} className={`num${c === 'd90_plus' && Number(r[c]) ? ' vencida' : ''}`}>{m(r[c])}</td>
                    ))}
                    {/* El saldo contable solo se enseña cuando no cuadra con las facturas: es lo que hay que revisar */}
                    <td className="num fuerte">
                      {money(r.total, language)}
                      {unmatched(r) && (
                        <span className="descuadre" title={t('aging.unmatchedHelp')}>
                          {t('aging.accountIs').replace('{a}', money(r.account_balance, language))}
                        </span>
                      )}
                    </td>
                  </tr>
                ))}
                <tr className="total">
                  <td><strong>{t('total')}</strong></td>
                  {cols.map((c) => <td key={c} className="num"><strong>{money(tot[c], language)}</strong></td>)}
                </tr>
              </tbody>
            </table>
          </div>
          {tot.unmatched > 0 && <p className="aviso">⚠ {t('aging.unmatchedNote').replace('{n}', tot.unmatched)}</p>}
        </>
      )}
    </section>
  )
}
