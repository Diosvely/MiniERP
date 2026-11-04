import { useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { reportText, runSteps } from '../synthetic'
import { useNotice } from '../notice'
import { SyntheticProgress } from './SyntheticCompany'

// v0.59.0 · En la cabecera de una empresa sintética: su semilla, perfil y meses, y «Copiar datos para informar de un
// error» (versión, semilla, perfil, meses, huella, pantalla y fecha de trabajo; nada personal)
// v0.59.1 · Si la generación se quedó a medias (synthetic_left > 0): «Continuar la generación», con su progreso.
export default function SyntheticInfo({ company, onDone }) {
  const { t, language } = useI18n()
  const notice = useNotice()
  const [running, setRunning] = useState(null)   // progreso mientras continúa
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

  async function resume() {
    setRunning({ done: 0, total: company.synthetic_left })
    const step = (id, n) => supabase.rpc('synthetic_step', { p_company: id, p_max: n })
    const res = await runSteps(step, company.id, { onProgress: setRunning })
    setRunning(null)
    if (res.error) return notice.error(res.error, { company })
    notice.success({ title: t('notice.syntheticDone'), lines: [company.name,
      t('notice.entries').replace('{n}', res.data.entries), t('notice.fingerprint').replace('{f}', res.data.fingerprint)] })
    onDone?.()
  }

  return (
    <div className="sintetica-cabecera">
      <span className="insignia insignia-sintetica" title={t('syn.badgeHelp')}>
        🎲 {t('syn.badge').replace('{seed}', company.synthetic_seed)
          .replace('{profile}', t(`syn.profile.${company.synthetic_profile}`)).replace('{n}', company.synthetic_months)}
      </span>
      {company.synthetic_left > 0 && !running && (
        <span className="aviso-temporal">⏳ {t('syn.left').replace('{n}', company.synthetic_left)}{' '}
          <button type="button" onClick={resume}>{t('syn.continue')}</button></span>)}
      {running && <SyntheticProgress progress={running} />}
      <button type="button" className="enlace" onClick={copy}>📋 {t('syn.copyReport')}</button>
      {state === 'copied' && <span className="exito" role="status">✓ {t('syn.copied')}</span>}
      {state === 'shown' && (
        <textarea readOnly className="sintetica-informe" rows={8} value={text} aria-label={t('syn.copyReport')}
                  onFocus={(e) => e.target.select()} />)}
    </div>
  )
}
