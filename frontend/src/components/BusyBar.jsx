import { useBusy } from '../activity'
import { useI18n } from '../i18n'

// Barra fina arriba y "Cargando…" mientras llegan datos de cualquier pantalla (ninguna se queda en blanco sin aviso)
export default function BusyBar() {
  const { t } = useI18n()
  const busy = useBusy()
  if (!busy) return null
  return (
    <div className="ocupado" role="status" aria-live="polite">
      <span className="ocupado-barra" aria-hidden="true" />
      <span className="ocupado-texto">{t('loadingData')}…</span>
    </div>
  )
}
