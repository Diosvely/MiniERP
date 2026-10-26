import { useEffect, useMemo, useRef, useState } from 'react'
import { useI18n } from '../i18n'
import { useAi } from '../aiContext'
import { filterAccounts, firstAccount, nrvLabel, pgcPath, nrvPath } from '../pgc'
import { loadPgc } from '../pgcLoad'
import { BookMarked } from 'lucide-react'
import { ICON } from '../icons'
import ErrorBox from './ErrorBox'
import Loading from './Loading'
import PgcCard from './PgcCard'

// PANEL DEL PGC EN NUEVO ASIENTO (v0.48.0, decisión 1 de diseno-v0.48.0.md): la ficha de una cuenta sin salir del
// asiento, en un panel lateral como el de la IA (en el PC ancho, al lado; en el móvil, a pantalla completa).
//   · Se abre con el ⓘ de cada línea (o «?» en el campo de cuenta) o con el botón «PGC» de la cabecera.
//   · Buscador, enlaces entre cuentas y la norma de valoración, todo dentro del panel.
//   · «Abrir en el PGC completo» lo abre en otra pestaña, para no perder el asiento.
// Escape o ✕ lo cierran y el foco vuelve a donde estaba. Si se abre la IA, este panel se cierra (y al revés).
export default function PgcPanel({ open, account, stamp, onClose }) {
  const { t } = useI18n()
  const ai = useAi()
  const [pgc, setPgc] = useState(null)
  const [error, setError] = useState('')
  const [current, setCurrent] = useState(account)
  const [text, setText] = useState('')
  const [rule, setRule] = useState(null)
  const panel = useRef(null)
  const body = useRef(null)

  useEffect(() => {
    if (!open || pgc) return
    let alive = true
    loadPgc().then((d) => alive && setPgc(d), (e) => alive && setError(e.code === '42P01' || e.code === 'PGRST205' ? t('pgc.dbMissing') : e.message))
    return () => { alive = false }
  }, [open])   // eslint-disable-line react-hooks/exhaustive-deps
  // Cada vez que se abre con una cuenta, esa cuenta (y el foco dentro del panel)
  useEffect(() => {
    if (!open) return
    setCurrent(account); setText(''); setRule(null)   // eslint-disable-line react-hooks/set-state-in-effect
    if (ai.open) ai.setOpen(false)
  }, [open, account, stamp])   // eslint-disable-line react-hooks/exhaustive-deps
  // El foco, dentro del panel: en el título de la ficha (o en el buscador si no hay cuenta), cuando ya ha cargado
  useEffect(() => {
    if (!open || !pgc) return
    requestAnimationFrame(() => (panel.current?.querySelector(account ? '.pgc-titulo' : '#pgc-panel-buscar') ?? panel.current?.querySelector('#pgc-panel-buscar'))?.focus())
  }, [open, account, stamp, pgc])
  useEffect(() => { if (ai.open && open) onClose() }, [ai.open])   // eslint-disable-line react-hooks/exhaustive-deps

  const found = useMemo(() => (pgc && text.trim() ? filterAccounts(pgc.accounts, pgc.cards, { text }).slice(0, 30) : []), [pgc, text])
  const shown = pgc ? firstAccount(current, pgc.accounts) : null
  const focusTitle = () => requestAnimationFrame(() => panel.current?.querySelector('.pgc-titulo')?.focus())
  const go = (a) => { setCurrent(a); setText(''); setRule(null); body.current?.scrollTo?.({ top: 0 }); focusTitle() }
  const r = rule && pgc?.rules.find((x) => x.number === rule)

  return (
    <aside id="panel-pgc" ref={panel} className="panel-ia panel-pgc" hidden={!open} aria-label={t('pgc.title')} tabIndex={-1}
           onKeyDown={(e) => { if (e.key === 'Escape') { e.stopPropagation(); onClose() } }}>
      <div className="panel-ia-cabecera">
        <strong><BookMarked {...ICON} /> {t('pgc.title')}</strong>
        <button type="button" className="secundario cerrar" onClick={onClose} aria-label={t('pgc.close')}>✕</button>
      </div>
      <div className="panel-ia-contenido" ref={body}>
        <label htmlFor="pgc-panel-buscar" className="oculto">{t('search')}</label>
        <input id="pgc-panel-buscar" type="search" placeholder={t('pgc.search')} value={text} onChange={(e) => setText(e.target.value)} />
        <ErrorBox error={error} />
        {open && !pgc && !error && <Loading />}
        {text.trim() && pgc && (
          <ul className="pgc-lista pgc-resultados" aria-label={t('pgc.results')}>
            {found.length ? found.map((a) => (
              <li key={a.account}><button type="button" className="pgc-fila" onClick={() => go(a.account)}>
                <span className="pgc-mono">{a.account}</span> <span className="pgc-nombre">{a.name}</span></button></li>))
              : <li className="ayuda">{t('pgc.none')}</li>}
          </ul>)}
        {pgc && !text.trim() && (shown
          ? (
            <>
              {r && (
                <div className="pgc-tarjeta pgc-norma" role="note">
                  <span className="pgc-mono pgc-num">{nrvLabel(r.number)}</span>
                  <h3>{r.title}</h3>
                  <p>{r.summary}</p>
                  <a href={`#${nrvPath(r.number)}`} target="_blank" rel="noopener" className="enlace">{t('pgc.openFull')} ↗</a>{' · '}
                  <button type="button" className="enlace" onClick={() => setRule(null)}>{t('pgc.hideRule')}</button>
                </div>)}
              <PgcCard pgc={pgc} account={shown} onGo={go} onNrv={(n) => { setRule(n); body.current?.scrollTo?.({ top: 0 }) }} headingLevel={3} focusTitle />
              <p className="pgc-completo"><a href={`#${pgcPath(shown)}`} target="_blank" rel="noopener" className="enlace">{t('pgc.openFull')} ↗</a></p>
            </>)
          : <p className="ayuda">{current ? t('pgc.notFound').replace('{n}', current) : t('pgc.panelHelp')}</p>)}
      </div>
    </aside>
  )
}
