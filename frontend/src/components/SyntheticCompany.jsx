import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import Link from './Link'
import { companyPath } from '../router'
import { idleText, shortDateTime } from '../temporary'
import { PROFILES, fitMonths, monthName, monthsFor, parseSeed, progressPct, randomSeed, runSteps } from '../synthetic'

// v0.59.0 · Crear una empresa sintética: semilla, perfil y meses. La base de datos la crea (temporal o permanente,
// como al importar) y la llena con las funciones de cada módulo. card = importCard(temp_status, canCreate)
// v0.59.1 · Por tandas, con su progreso (Supabase corta cada llamada a los ~8 s). Al terminar, onCreated(resultado);
// si una tanda falla, onFailed(error, empresa): la empresa queda creada y se continúa desde su cabecera.
export default function SyntheticCompany({ card, temp, onCreated, onFailed }) {
  const { t, language } = useI18n()
  const [profiles, setProfiles] = useState(null)   // erp.synthetic_profiles (sin la migración 0086, la tarjeta no sale)
  const [seedText, setSeedText] = useState(() => String(randomSeed()))
  const [profile, setProfile] = useState('workshop')
  const [months, setMonths] = useState(12)
  const [busy, setBusy] = useState(false)
  const [progress, setProgress] = useState(null)   // la última respuesta de synthetic_step (done, total, date)

  useEffect(() => {
    let alive = true
    supabase.rpc('synthetic_profiles').then(({ data, error }) => { if (alive) setProfiles(error ? [] : data) })
    return () => { alive = false }
  }, [])
  if (!profiles?.length || !card.show) return null

  const seed = parseSeed(seedText)
  const info = profiles.find((p) => p.profile === profile)

  async function create(e) {
    e.preventDefault()
    if (!seed) return
    setBusy(true)
    setProgress(null)
    // 1) la empresa preparada y su plan (rápido)
    const { data: made, error } = await supabase.rpc('create_synthetic_company', { p_seed: seed, p_profile: profile, p_months: months })
    if (error) { setBusy(false); return onFailed(error, null) }
    setProgress({ done: 0, total: made.total })
    // 2) las tandas, con su progreso
    const step = (id, n) => supabase.rpc('synthetic_step', { p_company: id, p_max: n })
    const res = await runSteps(step, made.company_id, { onProgress: setProgress })
    setBusy(false)
    setProgress(null)
    if (res.error) return onFailed(res.error, made)
    onCreated({ ...made, ...res.data })
  }

  return (
    <form className="tarjeta sintetica" onSubmit={create}>
      <h2>🎲 {t('syn.title')}</h2>
      <p className="ayuda">{t('syn.help')}</p>
      {card.temporary && !card.blocked && (
        <p className="ayuda">⏳ {t('syn.temporary').replace('{hours}', temp.max_hours).replace('{idle}', idleText(temp.idle_minutes))}</p>)}
      {card.blocked === 'hasTemp' && (
        <p className="aviso">⏳ {t('tmp.hasTemp').replace('{name}', temp.company.name)
          .replace('{date}', shortDateTime(temp.company.expires_at, language)).replace('{idle}', idleText(temp.idle_minutes))}{' '}
          <Link to={companyPath(temp.company.id)} className="enlace">{t('tmp.open')} →</Link></p>)}
      {card.blocked === 'full' && <p className="aviso" role="status">⏳ {t('tmp.full')}</p>}

      <label htmlFor="sin-semilla">{t('syn.seed')}</label>
      <div className="fila">
        <input id="sin-semilla" inputMode="numeric" value={seedText} aria-describedby="sin-semilla-ayuda"
               aria-invalid={!seed} onChange={(e) => setSeedText(e.target.value)} />
        <button type="button" className="secundario" onClick={() => setSeedText(String(randomSeed()))}>🎲 {t('syn.another')}</button>
      </div>
      <p id="sin-semilla-ayuda" className={seed ? 'ayuda' : 'aviso'}>{seed ? t('syn.seedHelp') : t('syn.seedInvalid')}</p>

      <label htmlFor="sin-perfil">{t('syn.profileLabel')}</label>
      <select id="sin-perfil" value={profile} aria-describedby="sin-perfil-ayuda"
              onChange={(e) => { setProfile(e.target.value); setMonths((m) => fitMonths(e.target.value, m)) }}>
        {PROFILES.filter((p) => profiles.some((x) => x.profile === p)).map((p) => (
          <option key={p} value={p}>{t(`syn.profile.${p}`)} · {t(`syn.tax.${profiles.find((x) => x.profile === p).tax_type}`)}</option>))}
      </select>
      <p id="sin-perfil-ayuda" className="ayuda">{language === 'en' ? info?.description_en : info?.description}</p>

      <label htmlFor="sin-meses">{t('syn.months')}</label>
      <select id="sin-meses" value={months} onChange={(e) => setMonths(Number(e.target.value))}>
        {monthsFor(profile).map((m) => <option key={m} value={m}>{m === 1 ? t('syn.monthsOne') : t('syn.monthsOption').replace('{month}', monthName(m, language))}</option>)}
      </select>
      <p className="ayuda">{t('syn.monthsHelp')}</p>

      <button type="submit" disabled={!seed || busy || Boolean(card.blocked)}>
        {busy ? `${t('syn.creating')}…` : t('syn.create')}
      </button>
      {progress && <SyntheticProgress progress={progress} />}
    </form>
  )
}

// La barra de progreso (también en la cabecera, al continuar una generación a medias)
export function SyntheticProgress({ progress }) {
  const { t, language } = useI18n()
  const pct = progressPct(progress)
  const month = progress.date ? monthName(Number(progress.date.slice(5, 7)), language) : null
  return (
    <div className="sintetica-progreso" role="status">
      <div className="progreso" aria-hidden="true"><span style={{ width: `${pct}%` }} /></div>
      <p className="ayuda">{t('syn.progress').replace('{month}', month ?? '…').replace('{pct}', pct)
        .replace('{done}', progress.done).replace('{total}', progress.total)}</p>
    </div>
  )
}
