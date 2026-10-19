import { useEffect, useId, useLayoutEffect, useRef, useState } from 'react'
import { useI18n } from '../i18n'
import { SOURCES, isStale } from '../sources'
import { shortDate } from '../format'
import { todayIso } from '../workDate'

// FUENTES OFICIALES (v0.39.0): <Sources ids={['aeat303', 'liva']} /> pinta el botón «📘 Fuentes» y, al pulsarlo,
// la lista de normas e instrucciones en las que se apoya la pantalla, con su enlace oficial (se abre en otra pestaña),
// el artículo que se usa y la fecha en que se comprobó. Se cierra con Escape o al tocar fuera.
export default function Sources({ ids }) {
  const { t, language } = useI18n()
  const [open, setOpen] = useState(false)
  const wrap = useRef(null)
  const panel = useRef(null)
  const panelId = useId()
  const list = (ids ?? []).map((id) => [id, SOURCES[id]]).filter(([, s]) => s)

  useEffect(() => {
    if (!open) return
    const onKey = (e) => { if (e.key === 'Escape') setOpen(false) }
    const onDown = (e) => { if (!wrap.current?.contains(e.target)) setOpen(false) }
    document.addEventListener('keydown', onKey)
    document.addEventListener('pointerdown', onDown)
    return () => { document.removeEventListener('keydown', onKey); document.removeEventListener('pointerdown', onDown) }
  }, [open])

  // Que no se salga de la pantalla (móvil): se mide y se desplaza hacia dentro, como el globo del glosario
  useLayoutEffect(() => {
    const el = panel.current
    if (!open || !el) return
    el.style.transform = ''
    const r = el.getBoundingClientRect()
    const margin = 8
    if (r.right > window.innerWidth - margin) el.style.transform = `translateX(${window.innerWidth - margin - r.right}px)`
    else if (r.left < margin) el.style.transform = `translateX(${margin - r.left}px)`
  }, [open])

  if (list.length === 0) return null
  const today = todayIso()
  return (
    <div className="fuentes" ref={wrap}>
      <button type="button" className="fuentes-boton" aria-expanded={open} aria-controls={panelId} onClick={() => setOpen((o) => !o)}>
        📘 {t('src.button')}
      </button>
      {open && (
        <div className="fuentes-panel" ref={panel} id={panelId} role="region" aria-label={t('src.title')}>
          <strong>{t('src.title')}</strong>
          <ul>
            {list.map(([id, s]) => {
              const x = s[language] ?? s.es
              return (
                <li key={id}>
                  <a href={s.url} target="_blank" rel="noopener noreferrer">{x.title}</a>
                  <small>{s.issuer} · {x.ref}</small>
                  <small className={isStale(s, today) ? 'fuente-revisar' : ''}>
                    {t(isStale(s, today) ? 'src.stale' : 'src.checked').replace('{d}', shortDate(s.checked))}
                  </small>
                </li>
              )
            })}
          </ul>
          <small>{t('src.note')}</small>
        </div>
      )}
    </div>
  )
}
