import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import CompanyView from './CompanyView'

const emptyForm = { name: '', vat_registration_no: '', industry: 'services', tax_territory: 'canary_islands' }

// Lista de empresas: las mías + las de demostración (solo lectura) + alta de empresa
export default function Companies({ session }) {
  const { t } = useI18n()
  const [companies, setCompanies] = useState([])
  const [profile, setProfile] = useState(null)   // { app_role, max_companies, companies_created }
  const [form, setForm] = useState(emptyForm)
  const [error, setError] = useState('')
  const [selected, setSelected] = useState(null)  // empresa abierta
  const [copied, setCopied] = useState(false)     // enlace de la demo copiado

  async function load() {
    // v_my_companies devuelve también mi rol en cada empresa (null = demo ajena → solo lectura)
    const { data, error } = await supabase.from('v_my_companies').select('*').order('name')
    if (error) return setError(error.message)
    setCompanies(data)
    const { data: p } = await supabase.rpc('my_profile').single()
    setProfile(p)
  }

  useEffect(() => { load() }, [])

  async function create(e) {
    e.preventDefault()
    setError('')
    // 1) Alta de la empresa (la base de datos copia el PGC, te hace admin y controla el límite)
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

  const mine = companies.filter((c) => c.my_role)
  const demos = companies.filter((c) => c.is_demo && !c.my_role)
  const isOwner = profile?.app_role === 'owner'
  const isGuest = Boolean(session.user.is_anonymous)
  const demoLink = `${window.location.origin}/?demo`
  const canCreate = profile && (profile.max_companies === null || profile.companies_created < profile.max_companies)

  // Si hay una empresa abierta, mostramos su pantalla en lugar de la lista
  if (selected) {
    const readOnly = !selected.my_role || selected.my_role === 'viewer'
    return (
      <CompanyView
        company={selected}
        readOnly={readOnly}
        canPublish={isOwner && selected.my_role === 'admin'}
        onChanged={(c) => setSelected(c)}
        onBack={() => { setSelected(null); load() }}
      />
    )
  }

  const item = (c) => (
    <li key={c.id} className="clicable" onClick={() => setSelected(c)}>
      <strong>
        {c.name} {c.is_demo && <span className="insignia">{t('demoBadge')}</span>}
      </strong>
      <span>
        {[c.vat_registration_no, t(`industry.${c.industry}`), t(`territory.${c.tax_territory}`)].filter(Boolean).join(' · ')}
      </span>
    </li>
  )

  return (
    <>
      <p className="usuario">
        {isGuest ? `👁 ${t('guestUser')}` : session.user.email}
        <button className="secundario" onClick={() => supabase.auth.signOut()}>
          {isGuest ? t('signUpToCreate') : t('signOut')}
        </button>
      </p>

      {isGuest && <p className="solo-lectura">{t('guestBanner')}</p>}

      {!isGuest && (
        <section className="tarjeta">
          <h2>{t('myCompanies')}</h2>
          {mine.length === 0 && <p>{t('noCompanies')}</p>}
          <ul>{mine.map(item)}</ul>
        </section>
      )}

      {demos.length > 0 && (
        <section className="tarjeta">
          <h2>{t('demoCompanies')}</h2>
          <p className="ayuda">{t('demoHelp')}</p>
          <ul>{demos.map(item)}</ul>
        </section>
      )}

      {/* El propietario ve el enlace para compartir las demos */}
      {isOwner && (
        <section className="tarjeta">
          <h2>{t('shareDemo')}</h2>
          <p className="ayuda">{t('shareDemoHelp')}</p>
          <div className="fila">
            <input readOnly value={demoLink} onFocus={(e) => e.target.select()} />
            <button type="button" className="secundario"
                    onClick={() => navigator.clipboard?.writeText(demoLink).then(() => setCopied(true))}>
              {copied ? '✓' : t('copy')}
            </button>
          </div>
        </section>
      )}

      {isGuest ? null : canCreate ? (
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
      ) : (
        profile && <p className="ayuda">{t('companyLimit').replace('{n}', profile.max_companies)}</p>
      )}

      {error && <p className="aviso">⚠ {error}</p>}
    </>
  )
}