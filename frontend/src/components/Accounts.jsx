import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { accountName } from '../format'

// Plan de cuentas de la empresa + alta de subcuentas
export default function Accounts({ company }) {
  const { t, language } = useI18n()
  const [accounts, setAccounts] = useState([])
  const [filter, setFilter] = useState('')
  const [form, setForm] = useState({ account_no: '', name: '', name_en: '' })
  const [error, setError] = useState('')

  async function load() {
    const { data, error } = await supabase
      .from('gl_accounts')
      .select('id, account_no, name, name_en, account_type, account_category')
      .eq('company_id', company.id)
      .order('account_no')
    if (error) setError(error.message)
    else setAccounts(data)
  }

  useEffect(() => { load() }, [company.id])

  async function create(e) {
    e.preventDefault()
    setError('')
    const { error } = await supabase.rpc('create_posting_account', {
      p_company: company.id,
      p_account_no: form.account_no,
      p_name: form.name,
      p_name_en: form.name_en || null,
    })
    if (error) return setError(error.message)
    setForm({ account_no: '', name: '', name_en: '' })
    setFilter(form.account_no.slice(0, 3))   // muestra la cuenta recién creada
    load()
  }

  // Filtro: por número que empiece igual o por texto dentro del nombre
  const f = filter.trim().toLowerCase()
  const visible = accounts.filter((a) =>
    !f || a.account_no.startsWith(f) || accountName(a, language).toLowerCase().includes(f))

  const change = (field) => (e) => setForm({ ...form, [field]: e.target.value })

  return (
    <>
      <form onSubmit={create} className="tarjeta">
        <h2>{t('newAccount')}</h2>
        <p className="ayuda">{t('newAccountHelp').replace('{n}', company.posting_account_digits)}</p>
        <input placeholder={t('accountNo')} value={form.account_no} inputMode="numeric"
               maxLength={company.posting_account_digits} onChange={change('account_no')} required />
        <input placeholder={t('accountNameEs')} value={form.name} onChange={change('name')} required />
        <input placeholder={t('accountNameEn')} value={form.name_en} onChange={change('name_en')} />
        <button type="submit">{t('createAccount')}</button>
        {error && <p className="aviso">⚠ {error}</p>}
      </form>

      <section className="tarjeta">
        <h2>{t('chartOfAccounts')} ({visible.length})</h2>
        <input placeholder={t('searchAccount')} value={filter} onChange={(e) => setFilter(e.target.value)} />
        <ul className="cuentas">
          {visible.map((a) => (
            <li key={a.id} className={a.account_type === 'posting' ? 'subcuenta' : `nivel-${Math.min(a.account_no.length, 4)}`}>
              <span className="codigo">{a.account_no}</span>
              <span>{accountName(a, language)}</span>
            </li>
          ))}
        </ul>
      </section>
    </>
  )
}