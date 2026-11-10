import { useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { useNotice } from '../notice'
import ErrorBox from './ErrorBox'
import Turnstile, { CAPTCHA_KEY } from './Turnstile'
import {
  ArrowDown, BarChart3, Bot, BriefcaseBusiness, Calculator, CircleCheck, CirclePlay, Code2, Eye, LayoutDashboard,
  MailCheck, SearchCheck, Upload,
} from 'lucide-react'
import { ICON } from '../icons'
import { FEATURES, LINKEDIN, REPO, WHY, YOUTUBE, scrollToSection } from '../landing'

const MIN_PASSWORD = 8   // el mismo mínimo que "Cambiar contraseña"
const FEATURE_ICONS = { accounting: Calculator, reports: BarChart3, dashboards: LayoutDashboard, ai: Bot,
  trace: SearchCheck, import: Upload }

// PANTALLA DE ENTRADA (sin sesión). v0.59.3: portada con la demo arriba y una captura de la aplicación (empresa sintética, datos
// ficticios), las 6 funciones, «¿Por qué MiniERP?» junto al acceso, una banda final y el pie con los enlaces del autor.
// La lógica de entrar, crear cuenta, invitado y CAPTCHA es la de v0.26.0 / v0.28.0; solo cambia que el alta y el error
// del invitado se confirman en el cuadro de diálogo (v0.59.1).
export default function Landing() {
  const { t, language } = useI18n()
  const notice = useNotice()
  const [tab, setTab] = useState('signin')       // 'signin' | 'signup'
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [show, setShow] = useState(false)        // mostrar la contraseña
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [sent, setSent] = useState(false)        // cuenta creada: falta confirmar el correo
  // CAPTCHA (Turnstile): un token por intento. Sin clave configurada no se pide.
  const [token, setToken] = useState(null)
  const [round, setRound] = useState(0)          // al cambiar, el widget pide un token nuevo
  const waiting = Boolean(CAPTCHA_KEY) && !token
  const captcha = CAPTCHA_KEY ? { captchaToken: token } : undefined
  const used = () => setRound((r) => r + 1)
  const fromLink = new URLSearchParams(window.location.search).has('demo')   // llegó con ?demo

  const reset = (next) => { setTab(next); setError(''); setSent(false); setShow(false) }

  // Invitado: sesión anónima de Supabase, solo puede ver las empresas demo
  async function guest() {
    setError(''); setBusy(true)
    const { error } = await supabase.auth.signInAnonymously({ options: captcha })
    setBusy(false); used()
    if (error) notice.error(error, { before: t('landingGuestFailed') })
  }

  async function submit(e) {
    e.preventDefault()
    setError('')
    if (tab === 'signup' && password.length < MIN_PASSWORD) return setError(t('passwordShort'))
    setBusy(true)
    if (tab === 'signin') {
      const { error } = await supabase.auth.signInWithPassword({ email, password, options: captcha })
      setBusy(false); used()
      if (error) setError(error.message)
      return
    }
    const { data, error } = await supabase.auth.signUp({ email, password, options: captcha })
    setBusy(false); used()
    if (error) return notice.error(error, { before: t('landingSignUpFailed') })
    // Con la confirmación por correo activada, Supabase no abre sesión hasta que se pulsa el enlace
    if (!data.session) {
      setSent(true); setPassword('')
      notice.success({ title: t('landingAccountCreated'),
        lines: [t('landingCheckEmail').replace('{e}', email), t('landingCheckEmailHelp')] })
    }
  }

  const long = password.length >= MIN_PASSWORD
  const demoButton = (autoFocus) => (
    <button type="button" className={fromLink ? 'boton-demo resaltado' : 'boton-demo'} autoFocus={autoFocus && fromLink}
            disabled={busy || waiting} onClick={guest}><Eye {...ICON} /> {t('viewDemo')}</button>
  )

  return (
    <div className="entrada">
      {/* ---------- Portada ---------- */}
      <section className="portada-hero" aria-labelledby="portada-titulo">
        <div className="portada-texto">
          <h2 id="portada-titulo">{t('landingTitle')}</h2>
          <p className="entrada-sub">{t('landingSubtitle')}</p>
          <div className="portada-botones">
            {demoButton(true)}
            <button type="button" className="secundario" onClick={() => scrollToSection('funciones')}>
              <ArrowDown {...ICON} /> {t('landingMore')}
            </button>
          </div>
          <Turnstile onToken={setToken} resetKey={round} language={language} />
          {waiting && <p className="ayuda captcha-espera" role="status">{t('captchaWaiting')}</p>}
          <ul className="portada-confianza" aria-label={t('landingTrustLabel')}>
            {t('landingTrust').map((x) => <li key={x}><CircleCheck {...ICON} /> {x}</li>)}
          </ul>
        </div>
        <figure className="portada-captura">
          <picture>
            <source srcSet="/portada-tablero-dark.webp" media="(prefers-color-scheme: dark)" />
            <img src="/portada-tablero-light.webp" width="1626" height="729" alt={t('landingShotAlt')} />
          </picture>
          <figcaption>{t('landingShotCaption')}</figcaption>
        </figure>
      </section>

      {/* ---------- Funciones ---------- */}
      <section id="funciones" className="portada-seccion" aria-labelledby="funciones-titulo">
        <h2 id="funciones-titulo">{t('landingFeaturesTitle')}</h2>
        <ul className="portada-funciones">
          {FEATURES.map((k) => {
            const Icon = FEATURE_ICONS[k]
            return (
              <li key={k} className="tarjeta">
                <span className="portada-icono"><Icon size={22} strokeWidth={1.75} aria-hidden="true" /></span>
                <strong>{t(`landingFeature.${k}.title`)}</strong>
                <span>{t(`landingFeature.${k}.text`)}</span>
              </li>
            )
          })}
        </ul>
      </section>

      {/* ---------- Por qué MiniERP + acceso ---------- */}
      <section className="portada-seccion portada-por-que">
        <div>
          <h2 id="por-que-titulo">{t('landingWhyTitle')}</h2>
          <ul className="portada-lista" aria-labelledby="por-que-titulo">
            {WHY.map((k) => (
              <li key={k}><CircleCheck size={20} strokeWidth={1.75} aria-hidden="true" className="entrada-icono" />
                <div><strong>{t(`landingWhy.${k}.title`)}</strong><span>{t(`landingWhy.${k}.text`)}</span></div>
              </li>
            ))}
          </ul>
        </div>

        <section id="acceso" className="tarjeta entrada-acceso" aria-label={t('landingAccess')}>
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
              <p className="exito"><MailCheck {...ICON} /> {t('landingCheckEmail').replace('{e}', email)}</p>
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

              <button type="submit" disabled={busy || waiting}>
                {busy ? `${t('loadingData')}…` : t(tab === 'signin' ? 'signIn' : 'landingCreate')}
              </button>
              <ErrorBox error={error} />
            </form>
          )}
        </section>
      </section>

      {/* ---------- Banda final ---------- */}
      <section className="portada-banda" aria-labelledby="banda-titulo">
        <div>
          <h2 id="banda-titulo">{t('landingBandTitle')}</h2>
          <p>{t('landingDemoHelp')}</p>
        </div>
        {demoButton(false)}
      </section>

      {/* ---------- Pie ---------- */}
      <footer className="entrada-pie">
        <p className="portada-marca">MiniERP <span>{t('landingTagline')}</span></p>
        <p>{t('landingAbout')}</p>
        <nav className="pie-enlaces" aria-label={t('landingLinks')}>
          <a href={REPO} target="_blank" rel="noopener noreferrer"><Code2 {...ICON} /> GitHub</a>
          <a href={LINKEDIN} target="_blank" rel="noopener noreferrer"><BriefcaseBusiness {...ICON} /> LinkedIn</a>
          <a href={YOUTUBE} target="_blank" rel="noopener noreferrer"><CirclePlay {...ICON} /> YouTube</a>
        </nav>
        <p>Diosvely Pérez Arteaga</p>
      </footer>
    </div>
  )
}
