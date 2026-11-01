import { useI18n } from '../i18n'
import { companyPath } from '../router'
import { checkDetail, CHECK_ICON } from '../dashboards'
import Link from './Link'

// LISTA DE CONTROL (v0.57.0 · ADR 0057): el estado de la contabilidad a una fecha, fila a fila. Cada fila lleva su
// icono y su estado en texto (nunca solo el color), la cifra, qué significa y el enlace a la pantalla donde se arregla.
// Las cifras y la gravedad las decide la base de datos (erp.quality_checks); aquí solo se dibujan.
//   data: la respuesta de erp.dashboard_data · widget: la tarjeta (kind 'checklist', con widget.checklist)
export default function DashChecklist({ company, widget }) {
  const { t, language } = useI18n()
  const rows = widget.checklist ?? []
  const text = (o, f) => (language === 'en' ? o[`${f}_en`] || o[f] : o[f])
  return (
    <>
      <h3>{text(widget, 'label')}</h3>
      <ul className="lista-control">
        {rows.map((r) => (
          <li key={r.code} className={`control ${r.severity}`}>
            <span className="control-icono" aria-hidden="true">{CHECK_ICON[r.severity]}</span>
            <span className="control-texto">
              <strong>{text(r, 'label')}</strong>
              <span className="control-estado"> · {t(`dash.check.${r.severity}`)}</span>
              <small>{text(r, 'help')}</small>
            </span>
            <span className="control-cifra">
              {checkDetail(r, language, t)}
              {r.severity !== 'na' && (
                <Link to={companyPath(company.id, r.link)} className="enlace">{t(`dash.check.go.${r.link}`)}</Link>
              )}
            </span>
          </li>
        ))}
      </ul>
      {text(widget, 'help') && <p className="ayuda">{text(widget, 'help')}</p>}
    </>
  )
}
