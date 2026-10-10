import { useEffect, useId, useLayoutEffect, useRef, useState } from 'react'
import { useI18n } from '../i18n'
import { GLOSSARY } from '../glossary'
import Link from './Link'

// Término con explicación: <Term id="debit">Debe</Term> pinta "Debe ⓘ".
// El globo se abre al pasar el ratón (ordenador), al tocar ⓘ (móvil) o con Tab + Enter; se cierra con Escape,
// al tocar fuera o al salir el ratón. Nunca se sale de la pantalla: si no cabe, se desplaza hacia dentro.
export default function Term({ id, children }) {
  const { t, language } = useI18n()
  const [open, setOpen] = useState(false)
  const box = useRef(null)
  const wrap = useRef(null)
  const popId = useId()
  const g = GLOSSARY[id]

  // Escape o un toque fuera lo cierran
  useEffect(() => {
    if (!open) return
    const onKey = (e) => { if (e.key === 'Escape') setOpen(false) }
    const onDown = (e) => { if (!wrap.current?.contains(e.target)) setOpen(false) }
    document.addEventListener('keydown', onKey)
    document.addEventListener('pointerdown', onDown)
    return () => { document.removeEventListener('keydown', onKey); document.removeEventListener('pointerdown', onDown) }
  }, [open])

  // Que no se salga por los lados (móvil): se mide y se desplaza
  useLayoutEffect(() => {
    const el = box.current
    if (!open || !el) return
    el.style.transform = ''
    const r = el.getBoundingClientRect()
    const margin = 8
    if (r.right > window.innerWidth - margin) el.style.transform = `translateX(${window.innerWidth - margin - r.right}px)`
    else if (r.left < margin) el.style.transform = `translateX(${margin - r.left}px)`
  }, [open])

  if (!g) return children ?? null
  const e = g[language] ?? g.es
  const mouse = (fn) => (ev) => { if (ev.pointerType === 'mouse') fn() }

  return (
    <span className="termino" ref={wrap} onPointerEnter={mouse(() => setOpen(true))} onPointerLeave={mouse(() => setOpen(false))}>
      {children ?? e.term}
      <button type="button" className="termino-i" aria-expanded={open} aria-controls={popId}
              aria-label={`${t('glossaryWhatIs')} ${e.term}`} onClick={() => setOpen((o) => !o)}>ⓘ</button>
      {open && (
        <span role="tooltip" id={popId} className="globo" ref={box}>
          <strong>{e.term}</strong>
          <span>{e.def}</span>
          {e.ex && <span className="globo-ejemplo">{e.ex}</span>}
          <span className="globo-erp">BC: {g.bc} · SAP: {g.sap}</span>
          <Link to="/glosario" className="enlace">{t('glossaryAll')} →</Link>
        </span>
      )}
    </span>
  )
}
