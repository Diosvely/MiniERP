import { useI18n } from '../i18n'
import { cardKey, exampleTotals, glossaryFor, linkify, nrvLabel } from '../pgc'
import Term from './Term'

// FICHA DE UNA CUENTA DEL PGC DE ESTUDIO (v0.48.0): para qué sirve, cuándo se carga y se abona, su saldo, dónde aparece
// en las cuentas anuales, la norma de valoración, un asiento de ejemplo (IGIC 7 %) y el «Ojo».
// La usan la pantalla #/pgc y el panel de Nuevo asiento. onGo(cuenta) abre otra cuenta; onNrv(n), una norma.
export default function PgcCard({ pgc, account, onGo, onNrv, headingLevel = 2, focusTitle = false }) {
  const { t, language } = useI18n()
  const a = pgc.accountMap[account]
  if (!a) return <p className="ayuda">{t('pgc.notFound').replace('{n}', account)}</p>
  const key = cardKey(account, pgc.cards)
  const card = key ? pgc.cards[key] : null
  const sub = pgc.subgroups[a.subgroup]
  const grp = pgc.groups[a.account[0]]
  const H = `h${headingLevel}`
  const L = (text) => linkify(text, pgc.accounts).map((p, i) => (p.go
    ? <button key={i} type="button" className="enlace pgc-ir" onClick={() => onGo(p.go)}
              aria-label={t('pgc.openAccount').replace('{n}', p.go)}>{p.text}</button>
    : <span key={i}>{p.text}</span>))
  const fmt = (v) => (Number(v) ? new Intl.NumberFormat(language === 'en' ? 'en-GB' : 'es-ES', { minimumFractionDigits: 2, maximumFractionDigits: 2, useGrouping: 'always' }).format(v) : '')
  const terms = glossaryFor(account)
  const lines = card?.example_lines ?? []
  const totals = exampleTotals(lines)

  return (
    <article className="pgc-ficha" aria-labelledby={`pgc-titulo-${account}`}>
      <p className="pgc-codigo">{account}{key && key !== account ? ` · ${t('pgc.cardOf').replace('{n}', key)}` : ''}</p>
      <H id={`pgc-titulo-${account}`} className="pgc-titulo" tabIndex={focusTitle ? -1 : undefined}>{a.name}</H>
      <p className="pgc-migas">
        {grp && <>{t('pgc.group')} {grp.grp}: {grp.name}</>}{sub && <> › {sub.subgroup}: {sub.name}</>}
      </p>
      {card && !card.validated && <p className="pgc-pendiente">{t('pgc.pending')}</p>}
      {card ? (
        <>
          <p className="pgc-uso">{L(card.usage)}</p>
          <div className="pgc-lados">
            <section className="pgc-lado pgc-debe">
              <h3>{t('pgc.debits')}</h3>
              <ul>{(card.debits ?? []).map((x, i) => <li key={i}>{L(x)}</li>)}</ul>
            </section>
            <section className="pgc-lado pgc-haber">
              <h3>{t('pgc.credits')}</h3>
              <ul>{(card.credits ?? []).map((x, i) => <li key={i}>{L(x)}</li>)}</ul>
            </section>
          </div>
          <h3 className="pgc-seccion">{t('pgc.balance')}</h3>
          <p>{card.balance}</p>
        </>
      ) : <p className="ayuda">{t('pgc.noCard')}</p>}

      <h3 className="pgc-seccion">{t('pgc.where')}</h3>
      {a.statement_lines?.length
        ? <ul className="pgc-donde">{a.statement_lines.map((x) => <li key={x}>{x}</li>)}</ul>
        : <p className="ayuda">{t('pgc.nowhere')}</p>}

      {card?.nrv?.length > 0 && (
        <>
          <h3 className="pgc-seccion">{t('pgc.rules')}</h3>
          <div className="etiquetas">
            {card.nrv.map((n) => {
              const r = pgc.rules.find((x) => x.number === n)
              return <button key={n} type="button" className="pgc-etiqueta" onClick={() => onNrv(n)}>{nrvLabel(n)}{r ? ` · ${r.title}` : ''}</button>
            })}
          </div>
        </>
      )}

      {card && (lines.length > 0 || card.example_text) && (
        <>
          <h3 className="pgc-seccion">{t('pgc.example')}</h3>
          {card.example_text && <p>{L(card.example_text)}</p>}
          {lines.length > 0 && (
            <div className="pgc-tabla" tabIndex={0} role="region" aria-label={`${t('pgc.example')}: ${a.name}`}>
              <table>
                <caption className="oculto">{t('pgc.example')}: {a.name}</caption>
                <thead><tr><th scope="col">{t('pgc.subaccount')}</th><th scope="col">{t('pgc.name')}</th>
                  <th scope="col" className="num">{t('debit')}</th><th scope="col" className="num">{t('credit')}</th></tr></thead>
                <tbody>
                  {lines.map((l, i) => (
                    <tr key={i}><td className="pgc-mono">{l.subcuenta}</td><td>{l.nombre}</td>
                      <td className="num pgc-mono">{fmt(l.debe)}</td><td className="num pgc-mono">{fmt(l.haber)}</td></tr>))}
                </tbody>
                <tfoot><tr><th scope="row" colSpan={2}>{t('total')}</th>
                  <td className="num pgc-mono">{fmt(totals.debit)}</td><td className="num pgc-mono">{fmt(totals.credit)}</td></tr></tfoot>
              </table>
            </div>
          )}
        </>
      )}

      {card?.warning && (
        <div className="pgc-ojo" role="note"><strong>{t('pgc.warning')}</strong> {L(card.warning)}</div>
      )}

      {terms.length > 0 && (
        <>
          <h3 className="pgc-seccion">{t('pgc.glossary')}</h3>
          <p className="pgc-terminos">{terms.map((id) => <Term key={id} id={id} />)}</p>
        </>
      )}
    </article>
  )
}
