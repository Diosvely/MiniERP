import { useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { reportText } from '../synthetic'

// v0.59.0 · En la cabecera de una empresa sintética: su semilla, perfil y meses, y «Copiar datos para informar de un
// error» (versión, semilla, perfil, meses, huella, pantalla y fecha de trabajo; nada personal)
export default function SyntheticInfo({ company }) {
  const { t, language } = useI18n()
  const [state, setState] = useState(null)   // null · 'copied' · 'shown' (si el navegador no deja copiar)
  const [text, setText] = useState('')

  async function copy() {
    const { data } = await supabase.rpc('company_fingerprint', { p_company: company.id })
    const txt = reportText({ company, fingerprint: data, route: window.location.hash, language, t })
    setText(txt)
    try {
      await navigator.clipboard.writeText(txt)
      setState('copied')
    } catch {
      setState('shown')
    }
  }

  return (
    <div className="sintetica-cabecera">
      <span className="insignia insignia-sintetica" title={t('syn.badgeHelp')}>
        🎲 {t('syn.badge').replace('{seed}', company.synthetic_seed)
          .replace('{profile}', t(`syn.profile.${company.synthetic_profile}`)).replace('{n}', company.synthetic_months)}
      </span>
      <button type="button" className="enlace" onClick={copy}>📋 {t('syn.copyReport')}</button>
      {state === 'copied' && <span className="exito" role="status">✓ {t('syn.copied')}</span>}
      {state === 'shown' && (
        <textarea readOnly className="sintetica-informe" rows={8} value={text} aria-label={t('syn.copyReport')}
                  onFocus={(e) => e.target.select()} />)}
    </div>
  )
}
