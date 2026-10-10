import { useI18n } from '../i18n'
import { friendlyError } from '../errors'
import { companyPath } from '../router'
import Link from './Link'
import { AlertTriangle } from 'lucide-react'
import { ICON } from '../icons'

// Caja de error comprensible: qué ha pasado, qué hacer, botón a la pantalla donde se arregla
// y, plegado, el mensaje técnico original (útil para el auditor y para avisar de un fallo).
//   <ErrorBox error={error} company={company} />   (error vacío → no pinta nada)
export default function ErrorBox({ error, company }) {
  const { t, language } = useI18n()
  const f = friendlyError(error, t, language)
  if (!f) return null
  const tax = company?.tax_territory === 'canary_islands' ? 'IGIC' : 'IVA'
  const screen = f.to ? t(`nav.${f.to}.label`).replace('{tax}', tax) : ''
  return (
    <div className="caja-error" role="alert">
      <p className="caja-error-titulo"><AlertTriangle {...ICON} /> {f.title}</p>
      {f.hint && <p className="caja-error-pista">{f.hint}</p>}
      {f.to && company && (
        <Link to={companyPath(company.id, f.to)} className="boton secundario">{t('err.goTo')} {screen} →</Link>
      )}
      {f.technical && (
        <details>
          <summary>{t('err.technical')}</summary>
          <code>{f.technical}</code>
        </details>
      )}
    </div>
  )
}
