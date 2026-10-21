import { useEffect, useRef, useState } from 'react'
import { useI18n } from '../i18n'
import { useAi } from '../aiContext'
import EntryTutor from './EntryTutor'
import AiAnalyst from './AiAnalyst'
import Link from './Link'
import { companyPath } from '../router'
import { defaultTab, panelTabs } from '../aiPanel'

// PANEL DE IA (v0.41.2): botón flotante abajo a la derecha que abre un panel lateral (en el móvil, a pantalla
// completa) con las IA de la app, como el chat de una web:
//   · Tutor de asientos: una conversación; «Pasar al asiento» lleva la propuesta a Nuevo asiento
//   · Analista: interpreta el ejercicio de la pantalla abierta (EFE o Ratios)
// El panel no tapa nada en el PC ancho: se pone al lado. Escape lo cierra y el foco vuelve al botón.
// La conversación se queda mientras la empresa esté abierta (el panel solo se oculta) y no se guarda en ningún sitio.
export default function AiPanel({ company, canWrite, onDraft }) {
  const { t } = useI18n()
  const { allowed, topic, open, setOpen, asked, setAsked } = useAi()
  const [tab, setTab] = useState('tutor')
  const buttonRef = useRef(null)
  const panelRef = useRef(null)
  const tabs = panelTabs({ canWrite, topic })

  // Al abrir: la pestaña que pidió la pantalla (o la que toca) y el foco dentro del panel
  useEffect(() => {
    if (!open) return
    setTab(defaultTab({ canWrite, topic, asked }))   // eslint-disable-line react-hooks/set-state-in-effect
    setAsked(null)
  }, [open])   // eslint-disable-line react-hooks/exhaustive-deps
  // …y el foco en la caja de texto del Tutor (o en la pestaña abierta)
  useEffect(() => {
    if (!open) return
    const box = panelRef.current?.querySelector(`#contenido-${tab} textarea`)
    ;(box ?? panelRef.current?.querySelector('[role="tab"][aria-selected="true"]'))?.focus()
  }, [open, tab])

  // Al cerrar, el foco vuelve al botón (en el móvil el botón estaba oculto: se espera a que vuelva a verse)
  function close() { setOpen(false); requestAnimationFrame(() => buttonRef.current?.focus()) }
  // «Pasar al asiento»: en el PC ancho el panel se queda al lado; si tapa la pantalla (móvil, portátil), se cierra
  function draft(d) {
    onDraft(d)
    if (!window.matchMedia?.('(min-width: 1100px)').matches) setOpen(false)
  }

  if (!allowed) return null
  return (
    <>
      <button ref={buttonRef} type="button" className="boton-ia" aria-expanded={open} aria-controls="panel-ia"
              onClick={() => (open ? close() : setOpen(true))} title={t('aiPanelOpen')}>
        <span aria-hidden="true">✨</span> <span className="boton-ia-texto">{t('aiPanelButton')}</span>
      </button>
      <aside id="panel-ia" ref={panelRef} className="panel-ia" hidden={!open} aria-label={t('aiPanelTitle')}
             onKeyDown={(e) => { if (e.key === 'Escape') close() }}>
        <div className="panel-ia-cabecera">
          <strong>✨ {t('aiPanelTitle')}</strong>
          <button type="button" className="secundario cerrar" onClick={close} aria-label={t('aiPanelClose')}>✕</button>
        </div>
        <div role="tablist" className="panel-ia-pestanas" aria-label={t('aiPanelTitle')}>
          {tabs.map((x) => (
            <button key={x.id} type="button" role="tab" id={`pestana-${x.id}`} aria-selected={tab === x.id}
                    aria-controls={`contenido-${x.id}`} className={tab === x.id ? 'activa' : ''} onClick={() => setTab(x.id)}>
              {t(x.id === 'tutor' ? 'tutorTitle' : 'aiTitle')}
            </button>
          ))}
        </div>
        {/* El Tutor se queda montado (oculto) para no perder la conversación al cambiar de pestaña o de pantalla */}
        {canWrite && (
          <div role="tabpanel" id="contenido-tutor" aria-labelledby="pestana-tutor" hidden={tab !== 'tutor'} className="panel-ia-contenido">
            <EntryTutor company={company} onLoad={draft} />
          </div>
        )}
        <div role="tabpanel" id="contenido-analyst" aria-labelledby="pestana-analyst" hidden={tab !== 'analyst'} className="panel-ia-contenido">
          {topic?.kind === 'analyst'
            ? <AiAnalyst key={`${company.id}-${topic.year}`} company={company} year={topic.year} inPanel />
            : (
              <p className="ayuda">
                {t('aiPanelAnalystWhere')}{' '}
                <Link to={companyPath(company.id, 'cashflow')} className="enlace">{t('nav.cashflow.label')}</Link>{' · '}
                <Link to={companyPath(company.id, 'ratios')} className="enlace">{t('nav.ratios.label')}</Link>
              </p>
            )}
        </div>
      </aside>
    </>
  )
}

// En la pantalla (EFE, Ratios): el botón que abre el panel en el Analista con el ejercicio que estás viendo
export function AskAnalyst() {
  const { t } = useI18n()
  const { allowed, ask } = useAi()
  if (!allowed) return null
  return (
    <p className="pedir-ia">
      <button type="button" className="secundario" onClick={() => ask('analyst')}>✨ {t('aiPanelAskAnalyst')}</button>
    </p>
  )
}
