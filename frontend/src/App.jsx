import { useEffect, useState } from 'react'
import { supabase } from './supabase'
import { I18nProvider, useI18n } from './i18n'
import CompanyView from './components/CompanyView'

export default function App() {
  const [session, setSession] = useState(null)

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSession(data.session))
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
    </form>
  )
}

const emptyForm = { name: '', vat_registration_no: '', industry: 'services', tax_territory: 'canary_islands' }

function Companies({ session }) {
  const { t } = useI18n()
  const [companies, setCompanies] = useState([])
  const [form, setForm] = useState(emptyForm)
  const [error, setError] = useState('')
  const [selected, setSelected] = useState(null)   // empresa abierta

  async function load() {
    const { data, error } = await supabase
      .from('companies')
      .select('id, name, vat_registration_no, industry, tax_territory, posting_account_digits')
      .order('name')
    if (error) setError(error.message)
    else setCompanies(data)
  }

  useEffect(() => { load() }, [])

  async function create(e) {
    e.preventDefault()
    setError('')
    // 1) Alta de la empresa (la base de datos copia el PGC y te hace admin)
    const { data, error } = await supabase
      .from('companies')
      .insert({ ...form, created_by: session.user.id })
      .select('id')
      .single()
    if (error) return setError(error.message)

    // 2) Ejercicio del año en curso con sus 12 periodos
    const { error: e2 } = await supabase.rpc('create_fiscal_year', {
      p_company: data.id,
      p_year: new Date().getFullYear(),
    })
    if (e2) return setError(e2.message)

    setForm(emptyForm)
    load()
  }

  const change = (field) => (e) => setForm({ ...form, [field]: e.target.value })
  
  // Si hay una empresa abierta, mostramos su pantalla en lugar de la lista
  if (selected) return <CompanyView company={selected} onBack={() => setSelected(null)} />

  return (
    <>
      <p className="usuario">
        {session.user.email}
        <button className="secundario" onClick={() => supabase.auth.signOut()}>{t('signOut')}</button>
      </p>

      <section className="tarjeta">
        <h2>{t('myCompanies')}</h2>
        {companies.length === 0 && <p>{t('noCompanies')}</p>}
        <ul>
          {companies.map((c) => (
          <li key={c.id} className="clicable" onClick={() => setSelected(c)}>
              <strong>{c.name}</strong>
              <span>
                {c.vat_registration_no} · {t(`industry.${c.industry}`)} · {t(`territory.${c.tax_territory}`)}
              </span>
            </li>
          ))}
        </ul>
      </section>

      <form onSubmit={create} className="tarjeta">
        <h2>{t('newCompany')}</h2>
        <input placeholder={t('companyName')} value={form.name} onChange={change('name')} required />
        <input placeholder={t('vatNo')} value={form.vat_registration_no} onChange={change('vat_registration_no')} />
        <select value={form.industry} onChange={change('industry')}>
          {['services', 'retail', 'manufacturing', 'ecommerce'].map((i) => (
            <option key={i} value={i}>{t(`industry.${i}`)}</option>
          ))}
        </select>
        <select value={form.tax_territory} onChange={change('tax_territory')}>
          {['canary_islands', 'mainland'].map((tt) => (
            <option key={tt} value={tt}>{t(`territory.${tt}`)}</option>
          ))}
        </select>
        <button type="submit">{t('createCompany')}</button>
      </form>

      {error && <p className="aviso">⚠ {error}</p>}
    </>
  )
}