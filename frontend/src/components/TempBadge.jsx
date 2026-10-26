import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { idleText, shortDateTime } from '../temporary'

// EMPRESA TEMPORAL (v0.49.0): en la cabecera de la empresa, «⏳ Temporal» y cuándo se borra: tras 2 h sin usar la
// aplicación o, como muy tarde, en su fecha. Recuerda exportar a Excel lo que se quiera guardar.
export default function TempBadge({ company }) {
  const { t, language } = useI18n()
  const [idle, setIdle] = useState(120)
  useEffect(() => {
    supabase.from('temp_settings').select('idle_minutes').maybeSingle()
      .then(({ data }) => { if (data?.idle_minutes) setIdle(data.idle_minutes) })
  }, [])
  if (!company.temporary || !company.expires_at) return null
  const help = t('tmp.headerHelp').replace('{idle}', idleText(idle)).replace('{date}', shortDateTime(company.expires_at, language))
  return (
    <p className="aviso-temporal cabecera-temporal" role="note">
      <strong>⏳ {t('tmp.badge')}</strong> · {help}
    </p>
  )
}
