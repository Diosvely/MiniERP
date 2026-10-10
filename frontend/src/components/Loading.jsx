import { useI18n } from '../i18n'

// "Cargando…" con tres puntos animados: ninguna pantalla aparece en blanco mientras llegan los datos
export default function Loading({ text }) {
  const { t } = useI18n()
  return (
    <p className="cargando" role="status" aria-live="polite">
      {text ?? t('loadingData')}<span aria-hidden="true">…</span>
    </p>
  )
}
