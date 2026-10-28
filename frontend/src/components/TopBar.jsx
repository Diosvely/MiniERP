import { useEffect, useRef, useState } from 'react'
import { LayoutDashboard } from 'lucide-react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { ICON } from '../icons'
import { dashPath, textOf } from '../dashboards'
import Link from './Link'

// BARRA SUPERIOR (v0.52.0 · ADR 0052): encima del contenido de la empresa, en todas sus pantallas. Empieza con
// «Tableros ▾», que despliega los tableros del catálogo (erp.dashboards); irán subiendo más botones poco a poco.
// El menú lateral no cambia. Teclado: Intro o Espacio abre, ↑ ↓ se mueven por la lista, Escape cierra.
//   active: código del tablero que se está viendo (o null)
export default function TopBar({ company, active }) {
  const { t, language } = useI18n()
  const [open, setOpen] = useState(false)
  const [list, setList] = useState(null)
  const box = useRef(null)
  const button = useRef(null)

  useEffect(() => {
    let alive = true
    supabase.from('dashboards').select('code, label, label_en, description, description_en').order('sort')
      .then(({ data }) => { if (alive) setList(data ?? []) })
    return () => { alive = false }
  }, [])

  // Se cierra al pulsar fuera
  useEffect(() => {
    if (!open) return
    const close = (e) => { if (!box.current?.contains(e.target)) setOpen(false) }
    document.addEventListener('mousedown', close)
    return () => document.removeEventListener('mousedown', close)
  }, [open])

  function keys(e) {
    if (e.key === 'Escape' && open) { e.preventDefault(); setOpen(false); button.current?.focus(); return }
    if (!['ArrowDown', 'ArrowUp'].includes(e.key)) return
    const links = [...(box.current?.querySelectorAll('.barra-lista a') ?? [])]
    if (!links.length) { if (e.key === 'ArrowDown') { e.preventDefault(); setOpen(true) } return }
    e.preventDefault()
    const i = links.indexOf(document.activeElement)
    const next = e.key === 'ArrowDown' ? (i + 1) % links.length : (i <= 0 ? links.length - 1 : i - 1)
    links[next].focus()
  }

  return (
    <nav className="barra-superior" aria-label={t('dash.bar')} onKeyDown={keys}>
      <div className="barra-item" ref={box}>
        <button type="button" ref={button} className={active ? 'activa' : ''} aria-expanded={open} aria-controls="lista-tableros"
                onClick={() => setOpen(!open)}>
          <LayoutDashboard {...ICON} /> {t('dash.title')} <span aria-hidden="true">▾</span>
        </button>
        {open && (
          <ul id="lista-tableros" className="barra-lista">
            {list === null && <li className="ayuda">{t('loadingData')}…</li>}
            {list?.length === 0 && <li className="ayuda">{t('dash.none')}</li>}
            {list?.map((d) => (
              <li key={d.code}>
                <Link to={dashPath(company.id, d.code)} aria-current={active === d.code ? 'page' : undefined}
                      onClick={() => setOpen(false)}>
                  <strong>{textOf(d, 'label', language)}</strong>
                  {textOf(d, 'description', language) && <small>{textOf(d, 'description', language)}</small>}
                </Link>
              </li>
            ))}
          </ul>
        )}
      </div>
    </nav>
  )
}
