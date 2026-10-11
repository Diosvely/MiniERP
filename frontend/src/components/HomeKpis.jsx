import { useI18n } from '../i18n'
import { money } from '../format'
import { companyPath } from '../router'
import Link from './Link'
import CashChart from './CashChart'
import { Landmark, Receipt, TrendingUp, UserRoundPlus, Briefcase } from 'lucide-react'
import { ICON } from '../icons'

// INDICADORES DEL INICIO (v0.30.0): las 5 cifras que mira primero quien lleva o revisa una empresa,
// a la fecha de trabajo, y la evolución de la tesorería. Como el Role Center de Business Central o la Overview Page
// de SAP Fiori: cada cifra lleva al informe donde se ve el detalle.
// Los datos vienen de erp.home_kpis (0031): sin regularización ni cierre, así que un ejercicio cerrado no sale a 0.
// Nunca solo color: ▲ / ▼ y las palabras "Beneficio", "A ingresar"… dicen lo mismo que el verde o el rojo.
export default function HomeKpis({ company, kpis }) {
  const { t, language } = useI18n()
  const eur = (v) => `${money(v, language)} €`
  const to = (section) => companyPath(company.id, section)
  const tax = company.tax_territory === 'canary_islands' ? 'IGIC' : 'IVA'
  const form = tax === 'IGIC' ? '420' : '303'

  const cashChange = Number(kpis.cash) - Number(kpis.cash_start)
  const result = Number(kpis.result)
  const taxNet = Number(kpis.tax_output) - Number(kpis.tax_input)
  const up = (v) => (v >= 0 ? 'sube' : 'baja')
  const arrow = (v) => (v >= 0 ? '▲' : '▼')

  const tiles = [
    {
      key: 'cash', icon: Landmark, title: t('kpi.cash'), value: eur(kpis.cash), link: to('balance'), more: t('kpi.cashLink'),
      detail: <><span className={up(cashChange)}>{arrow(cashChange)} {eur(Math.abs(cashChange))}</span> {t('kpi.cashSince')}</>,
    },
    {
      key: 'result', icon: TrendingUp, title: t('kpi.result').replace('{y}', kpis.year), value: eur(result), link: to('pyg'),
      more: t('kpi.resultLink'),
      detail: <>
        <span className={up(result)}>{arrow(result)} {t(result >= 0 ? 'kpi.profit' : 'kpi.loss')}</span>
        {kpis.result_prev != null && <> · {kpis.year - 1}: {eur(kpis.result_prev)}</>}
      </>,
    },
    {
      key: 'tax', icon: Receipt, title: t('kpi.tax').replace('{tax}', tax).replace('{q}', kpis.quarter), value: eur(Math.abs(taxNet)),
      link: to('settlement'), more: t('kpi.taxLink').replace('{tax}', tax).replace('{form}', form),
      detail: <>{t(taxNet >= 0 ? 'kpi.taxPay' : 'kpi.taxRefund')} · {t('kpi.taxDetail')
        .replace('{o}', money(kpis.tax_output, language)).replace('{i}', money(kpis.tax_input, language))}</>,
    },
    {
      key: 'receivable', icon: UserRoundPlus, title: t('kpi.receivable'), value: eur(kpis.receivable), link: to('partners'),
      more: t('kpi.receivableLink'), detail: t('kpi.receivableDetail').replace('{n}', kpis.receivable_accounts),
    },
    {
      key: 'payable', icon: Briefcase, title: t('kpi.payable'), value: eur(kpis.payable), link: to('partners'),
      more: t('kpi.payableLink'), detail: t('kpi.payableDetail').replace('{n}', kpis.payable_accounts),
    },
  ]

  const date = new Date(`${kpis.date}T00:00:00`).toLocaleDateString(language === 'en' ? 'en-GB' : 'es-ES')

  return (
    <>
      <ul className="kpis" aria-label={t('kpi.listLabel').replace('{d}', date)}>
        {tiles.map(({ key, icon: Icon, title, value, detail, link, more }) => (
          <li key={key}>
            <Link to={link} className="kpi">
              <span className="kpi-titulo"><Icon {...ICON} size={16} /> {title}</span>
              <span className="kpi-valor">{value}</span>
              <span className="kpi-detalle">{detail}</span>
              <span className="kpi-pie">{more} →</span>
            </Link>
          </li>
        ))}
      </ul>
      {kpis.cash_months?.length >= 2 && <CashChart months={kpis.cash_months} year={kpis.year} />}
    </>
  )
}
