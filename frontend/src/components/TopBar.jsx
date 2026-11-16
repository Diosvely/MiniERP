import { useEffect, useRef, useState } from 'react'
import { LayoutDashboard, ShieldCheck } from 'lucide-react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { ICON } from '../icons'
import { dashPath, groupDashboards, textOf } from '../dashboards'
import Link from './Link'

// BARRA SUPERIOR (v0.52.0 · ADR 0052): encima del contenido de la empresa, en todas sus pantallas. Cada botón despliega
// los tableros del catálogo (erp.dashboards) de su grupo; irán subiendo más botones poco a poco.
// v0.60.7 · MENÚ «AUDITORÍAS» (ADR 0064): «Tableros ▾» con los de gestión y «Auditorías ▾» con los de auditor (Calidad
// de la contabilidad y Saldos al revés). Las direcciones de los tableros no cambian.
// El menú lateral no cambia. Teclado: Intro o Espacio abre, ↑ ↓ se mueven por la lista, Escape cierra.
//   active: código del tablero que se está viendo (o null)
export default function TopBar({ company, active }) {
  const { t } = useI18n()
  const [list, setList] = useState(null)

  useEffect(() => {
    let alive = true
    supabase.from('dashboards').select('code, label, label_en, description, description_en, area').order('sort')
      .then(({ data, error }) => {
        if (!alive) return
        if (!error) return setList(data ?? [])
        // Sin la migración 0096 todavía (no existe la columna area): todos como tableros
        supabase.from('dashboards').select('code, label, label_en, description, description_en').order('sort')
          .then(({ data: d }) => { if (alive) setList(d ?? []) })
      })
    return () => { alive = false }
  }, [])

  const groups = list === null ? null : groupDashboards(list)
  return (
    <nav className="barra-superior" aria-label={t('dash.bar')}>
      <Menu id="lista-tableros" icon={LayoutDashboard} title={t('dash.title')} empty={t('dash.none')}
            items={groups?.tablero ?? null} company={company} active={active} />
      {(groups === null || groups.auditoria.length > 0) && (
        <Menu id="lista-auditorias" icon={ShieldCheck} title={t('dash.audits')} empty={t('dash.none')}
              items={groups?.auditoria ?? null} company={company} active={active} />
      )}
    </nav>
  )
}

// Un botón de la barra con su lista desplegable
function Menu({ id, icon: Icon, title, empty, items, company, active }) {
  const { t, language } = useI18n()
  const [open, setOpen] = useState(false)
  const box = useRef(null)
  const button = useRef(null)
  const mine = items?.some((d) => d.code === active)

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
    <div className="barra-item" ref={box} onKeyDown={keys}>
      <button type="button" ref={button} className={mine ? 'activa' : ''} aria-expanded={open} aria-controls={id}
              onClick={() => setOpen(!open)}>
        <Icon {...ICON} /> {title} <span aria-hidden="true">▾</span>
      </button>
      {open && (
        <ul id={id} className="barra-lista">
          {items === null && <li className="ayuda">{t('loadingData')}…</li>}
          {items?.length === 0 && <li className="ayuda">{empty}</li>}
          {items?.map((d) => (
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
  )
}
