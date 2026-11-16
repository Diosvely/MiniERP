import { useState } from 'react'
import { useI18n } from '../i18n'
import { companyPath } from '../router'
import { money } from '../format'
import { cardLine, filterCards, reverseSummary, textOf } from '../dashboards'
import { readModel } from '../balanceModels'
import Link from './Link'

// SALDOS AL REVÉS (v0.60.7 · ADR 0064): una tarjeta por cada subcuenta con el saldo contrario a su naturaleza.
// Cada tarjeta: la cuenta, lo que debería ser, el importe, «imposible» o «revisar», dónde la pone el Balance (en el
// modelo elegido en la pantalla del Balance), la nota de la regla, la pregunta de un auditor y el enlace a su Mayor.
// Lo decide la base de datos (erp.reverse_cards, con las reglas de erp.balance_rules); aquí solo se dibuja.
//   data: la respuesta de erp.dashboard_data · widget: la tarjeta (kind 'reverse_cards', con widget.cards)
export default function DashReverse({ company, data, widget }) {
  const { t, language } = useI18n()
  const [filter, setFilter] = useState('all')
  const model = readModel()
  const cards = widget.cards ?? []
  const sum = reverseSummary(cards)
  const shown = filterCards(cards, filter)
  // Saldo deudor positivo: «1.800,00 D»; acreedor: «4.074,70 H»
  const side = (v) => `${money(Math.abs(Number(v)), language)} ${Number(v) >= 0 ? t('rev.d') : t('rev.h')}`

  return (
    <>
      <h3>{textOf(widget, 'label', language)}</h3>
      {cards.length === 0 && <p className="ayuda">{t('rev.none')}</p>}
      {cards.length > 0 && (
        <>
          <div className="reves-resumen" role="group" aria-label={t('rev.filter')}>
            {[['all', 'rev.all', sum.total], ['error', 'rev.errors', sum.errors], ['warning', 'rev.review', sum.review]].map(([f, k, n]) => (
              <button key={f} type="button" aria-pressed={filter === f} className={`reves-filtro ${f}${filter === f ? ' activa' : ''}`}
                      onClick={() => setFilter(f)}>
                <strong>{n}</strong> {t(k)}
              </button>
            ))}
          </div>
          <ul className="reves-tarjetas">
            {shown.map((c) => {
              const line = cardLine(c, model)
              return (
                <li key={c.account_no} className={`reves-tarjeta ${c.severity}`}>
                  <div className="reves-cabecera">
                    <span><span className="codigo">{c.account_no}</span> {textOf(c, 'name', language)}</span>
                    <span className={`reves-chip ${c.severity}`}>{c.severity === 'error' ? `✗ ${t('rev.chipError')}` : `⚠ ${t('rev.chipReview')}`}</span>
                  </div>
                  <p className="reves-importe">{side(c.balance)}
                    <small> · {t(c.expected === 'debit' ? 'rev.shouldDebit' : 'rev.shouldCredit')}</small></p>
                  {line && <p className="reves-donde">{t('rev.where').replace('{m}', t(`fsModel.${model}`))} <strong>{textOf(line, 'label', language)}</strong></p>}
                  {textOf(c, 'note', language) && <p className="reves-nota">{textOf(c, 'note', language)}</p>}
                  <p className="reves-pregunta">{t(c.severity === 'error' ? 'rev.askError' : 'rev.askReview')}</p>
                  <Link to={companyPath(company.id, `reports/mayor/${c.account_no}/${data.year}`)} className="enlace">{t('rev.ledger')}</Link>
                </li>
              )
            })}
          </ul>
        </>
      )}
      {textOf(widget, 'help', language) && <p className="ayuda">{textOf(widget, 'help', language)}</p>}
    </>
  )
}
