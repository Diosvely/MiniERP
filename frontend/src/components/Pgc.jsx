import { useEffect, useMemo, useRef, useState } from 'react'
import { useI18n } from '../i18n'
import { navigate } from '../router'
import { DEFAULT_ACCOUNT, cardKey, filterAccounts, firstAccount, nrvLabel, nrvPath, pgcPath, pgcRoute } from '../pgc'
import { loadPgc } from '../pgcLoad'
import { BookMarked } from 'lucide-react'
import { ICON } from '../icons'
import Term from './Term'
import Sources from './Sources'
import ErrorBox from './ErrorBox'
import Loading from './Loading'
import PgcCard from './PgcCard'

// PGC DE ESTUDIO (#/pgc · v0.48.0): el Plan General de Contabilidad para consultar mientras se estudia o se contabiliza.
//   · #/pgc/4000          → Cuentas: buscador, árbol (grupo › subgrupo › cuenta) y la ficha de la cuenta
//   · #/pgc/nrv/12        → Normas de registro y valoración, con la 12.ª resaltada
//   · #/pgc/principios    → Principios contables
// Solo lectura y común a todas las empresas (migración 0071). Textos propios, no literales: el oficial, en 📘 Fuentes.
const GROUPS = ['1', '2', '3', '4', '5', '6', '7', '8', '9']

export default function Pgc({ route }) {
  const { t } = useI18n()
  const [pgc, setPgc] = useState(null)
  const [error, setError] = useState('')
  const where = pgcRoute(route)

  useEffect(() => {
    let alive = true
    loadPgc().then((d) => alive && setPgc(d), (e) => alive && setError(e.code === '42P01' || e.code === 'PGRST205' ? t('pgc.dbMissing') : e.message))
    return () => { alive = false }
  }, [])   // eslint-disable-line react-hooks/exhaustive-deps

  const tabs = [['accounts', t('pgc.tabAccounts'), pgcPath(DEFAULT_ACCOUNT)], ['nrv', t('pgc.tabRules'), nrvPath()], ['principles', t('pgc.tabPrinciples'), '/pgc/principios']]
  return (
    <section className="tarjeta pgc">
      <div className="fila-glosario">
        <button type="button" className="secundario" onClick={() => window.history.back()}>← {t('glossaryBack')}</button>
        <h2><BookMarked {...ICON} /> <Term id="chart">{t('pgc.title')}</Term></h2>
        <Sources ids={['pgc']} />
      </div>
      <p className="ayuda">{t('pgc.intro')}</p>
      <div role="tablist" className="pestanas-acceso pgc-pestanas" aria-label={t('pgc.title')}>
        {tabs.map(([id, label, path]) => (
          <button key={id} type="button" role="tab" id={`pgc-tab-${id}`} aria-selected={where.tab === id} aria-controls="pgc-panel"
                  className={where.tab === id ? 'activa' : ''} onClick={() => navigate(path, { replace: true })}>{label}</button>))}
      </div>
      <ErrorBox error={error} />
      <div id="pgc-panel" role="tabpanel" aria-labelledby={`pgc-tab-${where.tab}`}>
        {!pgc ? (!error && <Loading />)
          : where.tab === 'nrv' ? <Rules pgc={pgc} highlight={where.nrv} />
            : where.tab === 'principles' ? <Principles pgc={pgc} />
              : <Accounts pgc={pgc} account={firstAccount(where.account ?? DEFAULT_ACCOUNT, pgc.accounts) ?? DEFAULT_ACCOUNT} />}
      </div>
    </section>
  )
}

function Accounts({ pgc, account }) {
  const { t } = useI18n()
  const [text, setText] = useState('')
  const [group, setGroup] = useState('')
  const [onlyCards, setOnlyCards] = useState(false)
  const list = useRef(null)
  const card = useRef(null)
  const shown = useMemo(() => filterAccounts(pgc.accounts, pgc.cards, { text, group, onlyCards }), [pgc, text, group, onlyCards])

  // Al abrir una cuenta desde un enlace, la lista la enseña; en el móvil, la página baja hasta la ficha
  const open = (a, { fromList = false } = {}) => {
    navigate(pgcPath(a), { replace: true })
    if (!fromList && !shown.some((x) => x.account === a)) { setText(''); setGroup(''); setOnlyCards(false) }
    if (window.matchMedia?.('(max-width: 800px)').matches) setTimeout(() => card.current?.scrollIntoView({ behavior: 'smooth', block: 'start' }), 0)
  }
  useEffect(() => {   // solo se mueve la lista, no la página
    const box = list.current, row = box?.querySelector('[aria-current="true"]')
    if (!box || !row) return
    const top = row.offsetTop   // .pgc-lista es position: relative
    if (top < box.scrollTop || top + row.offsetHeight > box.scrollTop + box.clientHeight) box.scrollTop = top - box.clientHeight / 3
  }, [account, shown])

  const rows = []
  let lastG = null, lastS = null
  for (const a of shown) {
    const g = a.account[0], s = a.account.slice(0, 2)
    if (g !== lastG) {
      rows.push(<li key={`g${g}`} className="pgc-grupo">{g}. {pgc.groups[g]?.name}
        {(g === '8' || g === '9') && <small>{t('pgc.equityGroups')}</small>}</li>)
      lastG = g
    }
    if (s !== lastS) { rows.push(<li key={`s${s}`} className="pgc-subgrupo">{s} · {pgc.subgroups[s]?.name}</li>); lastS = s }
    const has = cardKey(a.account, pgc.cards)
    rows.push(
      <li key={a.account}>
        <button type="button" className="pgc-fila" aria-current={a.account === account ? 'true' : undefined} onClick={() => open(a.account, { fromList: true })}>
          <span className="pgc-mono">{a.account}</span> <span className="pgc-nombre">{a.name}</span>
          {has && <span className="pgc-marca" aria-label={t('pgc.hasCard')}>● {t('pgc.card')}</span>}
        </button>
      </li>)
  }

  return (
    <div className="pgc-rejilla">
      <aside className="pgc-lateral" aria-label={t('pgc.tabAccounts')}>
        <label htmlFor="pgc-buscar" className="oculto">{t('search')}</label>
        <input id="pgc-buscar" type="search" placeholder={t('pgc.search')} value={text} onChange={(e) => setText(e.target.value)} />
        <div className="pgc-chips" role="group" aria-label={t('pgc.group')}>
          {['', ...GROUPS].map((g) => (
            <button key={g || 'all'} type="button" className={group === g ? 'activo' : ''} aria-pressed={group === g} onClick={() => setGroup(g)}>
              {g ? `${t('pgc.group')} ${g}` : t('pgc.all')}
            </button>))}
        </div>
        <label className="opcion"><input type="checkbox" checked={onlyCards} onChange={(e) => setOnlyCards(e.target.checked)} /> {t('pgc.onlyCards')}</label>
        <p className="ayuda" aria-live="polite">{t('pgc.count').replace('{n}', shown.length)}</p>
        <ul className="pgc-lista" ref={list}>
          {rows.length ? rows : <li className="ayuda">{t('pgc.none')}</li>}
        </ul>
      </aside>
      <div className="pgc-derecha" ref={card}>
        <PgcCard pgc={pgc} account={account} onGo={(a) => open(a)} onNrv={(n) => navigate(nrvPath(n))} />
      </div>
    </div>
  )
}

function Rules({ pgc, highlight }) {
  const { t } = useI18n()
  useEffect(() => {   // baja hasta la norma; el resaltado (1,6 s) lo hace el CSS
    if (highlight) document.getElementById(`nrv${highlight}`)?.scrollIntoView({ behavior: 'smooth', block: 'start' })
  }, [highlight])
  return (
    <>
      <p className="ayuda">{t('pgc.rulesIntro')}</p>
      <ol className="pgc-tarjetas">
        {pgc.rules.map((r) => (
          <li key={r.number} id={`nrv${r.number}`} className={`pgc-tarjeta${highlight === r.number ? ' resaltada' : ''}`}>
            <span className="pgc-mono pgc-num">{nrvLabel(r.number)}</span>
            <h3>{r.title}</h3>
            <p>{r.summary}</p>
            {(pgc.nrvRefs[r.number] ?? []).length > 0 && (
              <div className="etiquetas">
                {pgc.nrvRefs[r.number].map((c) => {
                  const a = firstAccount(c, pgc.accounts)
                  return <button key={c} type="button" className="pgc-etiqueta" onClick={() => navigate(pgcPath(a ?? c))}>
                    <span className="pgc-mono">{c}</span> {pgc.accountMap[a]?.name}</button>
                })}
              </div>)}
          </li>))}
      </ol>
    </>
  )
}

function Principles({ pgc }) {
  const { t } = useI18n()
  return (
    <>
      <p className="ayuda">{t('pgc.principlesIntro')}</p>
      <ol className="pgc-tarjetas">
        {pgc.principles.map((p) => (
          <li key={p.sort} className="pgc-tarjeta"><h3>{p.name}</h3><p>{p.description}</p></li>))}
      </ol>
    </>
  )
}
