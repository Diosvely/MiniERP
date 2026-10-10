import { useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import ErrorBox from './ErrorBox'

const REPO = 'https://github.com/Diosvely/MiniERP'
const MIN_PASSWORD = 8   // el mismo mínimo que "Cambiar contraseña"

// PANTALLA DE ENTRADA (sin sesión): qué es esto, ver la demo sin registrarse, o entrar / crear cuenta.
// Es lo primero que ve quien llega desde el portfolio: la demo va arriba y en grande.
export default function Landing() {
  const { t } = useI18n()
  const [tab, setTab] = useState('signin')       // 'signin' | 'signup'
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [show, setShow] = useState(false)        // mostrar la contraseña
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [sent, setSent] = useState(false)        // cuenta creada: falta confirmar el correo

  const reset = (next) => { setTab(next); setError(''); setSent(false); setShow(false) }

  // Invitado: sesión anónima de Supabase, solo puede ver las empresas demo
  async function guest() {
    setError(''); setBusy(true)
    const { error } = await supabase.auth.signInAnonymously()
    setBusy(false)
    if (error) setError(error.message)
  }

  async function submit(e) {
    e.preventDefault()
    setError('')
    if (tab === 'signup' && password.length < MIN_PASSWORD) return setError(t('passwordShort'))
    setBusy(true)
    if (tab === 'signin') {
      const { error } = await supabase.auth.signInWithPassword({ email, password })
      setBusy(false)
      if (error) setError(error.message)
      return
    }
    const { data, error } = await supabase.auth.signUp({ email, password })
    setBusy(false)
    if (error) return setError(error.message)
    // Con la confirmación por correo activada, Supabase no abre sesión hasta que se pulsa el enlace
    if (!data.session) { setSent(true); setPassword('') }
  }

  const long = password.length >= MIN_PASSWORD

  return (
    <div className="entrada">
      <section className="entrada-portada">
        <h2>{t('landingTitle')}</h2>
        <p className="entrada-sub">{t('landingSubtitle')}</p>
        <ul className="entrada-puntos">
          {['pgc', 'tax', 'audit'].map((k, i) => (
            <li key={k}>
              <span aria-hidden="true">{['📒', '🧾', '🔍'][i]}</span>
              <div><strong>{t(`landingPoint.${k}.title`)}</strong><span>{t(`landingPoint.${k}.text`)}</span></div>
            </li>
          ))}
        </ul>
        <button type="button" className="boton-demo" disabled={busy} onClick={guest}>👁 {t('viewDemo')}</button>
        <p className="ayuda">{t('landingDemoHelp')}</p>
      </section>

      <section className="tarjeta entrada-acceso">
        <div className="pestanas-acceso" role="tablist" aria-label={t('login')}>
          {['signin', 'signup'].map((k) => (
            <button key={k} type="button" role="tab" id={`tab-${k}`} aria-selected={tab === k} aria-controls="panel-acceso"
                    className={tab === k ? 'activa' : ''} onClick={() => reset(k)}>
              {t(k === 'signin' ? 'landingSignIn' : 'landingSignUp')}
            </button>
          ))}
        </div>

        {sent ? (
          <div id="panel-acceso" role="tabpanel" aria-labelledby="tab-signup" className="enviado">
            <p className="exito">✉ {t('landingCheckEmail').replace('{e}', email)}</p>
            <p className="ayuda">{t('landingCheckEmailHelp')}</p>
            <button type="button" className="secundario" onClick={() => reset('signin')}>{t('landingSignIn')}</button>
          </div>
        ) : (
          <form id="panel-acceso" role="tabpanel" aria-labelledby={`tab-${tab}`} onSubmit={submit}>
            <label htmlFor="acceso-email">{t('email')}</label>
            <input id="acceso-email" type="email" autoComplete="email" required value={email}
                   onChange={(e) => setEmail(e.target.value)} />

            <label htmlFor="acceso-password">{t('landingPassword')}</label>
            <div className="campo-password">
              <input id="acceso-password" type={show ? 'text' : 'password'} required value={password}
                     autoComplete={tab === 'signin' ? 'current-password' : 'new-password'}
                     aria-describedby={tab === 'signup' ? 'requisitos-password' : undefined}
                     onChange={(e) => setPassword(e.target.value)} />
              <button type="button" className="secundario" aria-pressed={show} onClick={() => setShow(!show)}>
                {show ? t('landingHide') : t('landingShow')}
              </button>
            </div>
            {tab === 'signup' && (
              <p id="requisitos-password" className={long ? 'requisito ok' : 'requisito'}>
                {long ? '✓' : '○'} {t('landingPasswordRule').replace('{n}', MIN_PASSWORD)}
              </p>
            )}

            <button type="submit" disabled={busy}>
              {busy ? `${t('loadingData')}…` : t(tab === 'signin' ? 'signIn' : 'landingCreate')}
            </button>
            <ErrorBox error={error} />
          </form>
        )}
      </section>

      <footer className="entrada-pie">
        <p>{t('landingAbout')}</p>
        <p>
          <a href={REPO} target="_blank" rel="noopener noreferrer">GitHub · Diosvely/MiniERP</a>
          {' · '}Diosvely Perez Arteaga
        </p>
      </footer>
    </div>
  )
}
