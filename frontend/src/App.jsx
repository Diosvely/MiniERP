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

function LanguageSwitch() {
  const { language, changeLanguage, t } = useI18n()
  return (
    <select aria-label={t('language')} value={language}
            onChange={(e) => changeLanguage(e.target.value)}>
      <option value="es">ES</option>
      <option value="en">EN</option>
    </select>
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

