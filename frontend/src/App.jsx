import { useEffect, useState } from 'react'
import { supabase } from './supabase'
import { I18nProvider, useI18n } from './i18n'
import Companies from './components/Companies'

export default function App() {
  const [session, setSession] = useState(null)

    useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session)
      // Enlace para compartir: https://…/?demo → entra como invitado sin registrarse
      if (!data.session && new URLSearchParams(window.location.search).has('demo')) {
        supabase.auth.signInAnonymously()
      }
    })
    const { data } = supabase.auth.onAuthStateChange((_event, s) => setSession(s))
    return () => data.subscription.unsubscribe()
  }, [])

  return (
    <I18nProvider session={session}>
      <Layout session={session} />
    </I18nProvider>
  )
}

function Layout({ session }) {
  const { t } = useI18n()
  return (
    <main>
      <header className="cabecera">
        <h1>{t('appTitle')}</h1>
        <LanguageSwitch />
      </header>
      {session ? <Companies session={session} /> : <Login />}
    </main>
  )
}

// Banderas dibujadas en SVG: Windows no muestra los emojis de banderas (🇪🇸 se ve como "ES")
function FlagES() {
  return (
    <svg viewBox="0 0 30 20" aria-hidden="true">
      <rect width="30" height="20" fill="#AA151B" />
      <rect y="5" width="30" height="10" fill="#F1BF00" />
    </svg>
  )
}

function FlagGB() {
  return (
    <svg viewBox="0 0 60 30" aria-hidden="true">
      <clipPath id="gb-diagonales"><path d="M30,15 h30 v15 z v15 h-30 z h-30 v-15 z v-15 h30 z" /></clipPath>
      <rect width="60" height="30" fill="#012169" />
      <path d="M0,0 L60,30 M60,0 L0,30" stroke="#fff" strokeWidth="6" />
      <path d="M0,0 L60,30 M60,0 L0,30" clipPath="url(#gb-diagonales)" stroke="#C8102E" strokeWidth="4" />
      <path d="M30,0 v30 M0,15 h60" stroke="#fff" strokeWidth="10" />
      <path d="M30,0 v30 M0,15 h60" stroke="#C8102E" strokeWidth="6" />
    </svg>
  )
}

// Selector de idioma con bandera, como el selector de idioma de las webs de los ERP
function LanguageSwitch() {
  const { language, changeLanguage, t } = useI18n()
  return (
    <div className="idiomas" role="group" aria-label={t('language')}>
      {[['es', 'ES', FlagES], ['en', 'EN', FlagGB]].map(([code, label, Flag]) => (
        <button key={code} type="button" className={language === code ? 'activo' : ''}
                aria-pressed={language === code} onClick={() => changeLanguage(code)}>
          <Flag /> {label}
        </button>
      ))}
    </div>
  )
}

function Login() {
  const { t } = useI18n()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [message, setMessage] = useState('')

  async function signIn(e) {
    e.preventDefault()
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) setMessage(error.message)
  }

    // Invitado: sesión anónima de Supabase, solo puede ver las empresas demo
  async function guest() {
    setMessage('')
    const { error } = await supabase.auth.signInAnonymously()
    if (error) setMessage(error.message)
  }

  async function signUp() {
    const { error } = await supabase.auth.signUp({ email, password })
    setMessage(error ? error.message : t('userCreated'))
  }

  return (
    <form onSubmit={signIn} className="tarjeta">
      <h2>{t('login')}</h2>
      <input type="email" placeholder={t('email')} value={email}
             onChange={(e) => setEmail(e.target.value)} required />
      <input type="password" placeholder={t('password')} value={password}
             onChange={(e) => setPassword(e.target.value)} required />
      <div className="fila">
        <button type="submit">{t('signIn')}</button>
        <button type="button" className="secundario" onClick={signUp}>{t('signUp')}</button>
      </div>
      {message && <p className="aviso">{message}</p>}
      <div className="invitado">
        <p className="ayuda">{t('guestHelp')}</p>
        <button type="button" className="secundario" onClick={guest}>👁 {t('viewDemo')}</button>
      </div>

    </form>
  )
}

