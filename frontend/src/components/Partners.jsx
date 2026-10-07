import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { money } from '../format'

const TYPES = ['customer', 'vendor', 'creditor', 'debtor']
const TERRITORIES = ['canary_islands', 'mainland', 'ceuta_melilla', 'eu', 'non_eu']

// Terceros: clientes, proveedores, acreedores y deudores, cada uno con su subcuenta
export default function Partners({ company, readOnly }) {
  const { t, language } = useI18n()
  const emptyForm = {
    type: 'customer', name: '', vat: '', territory: company.tax_territory,
    accountMode: 'auto', accountNo: '', email: '', surcharge: false,
  }
  const [partners, setPartners] = useState([])
  const [form, setForm] = useState(emptyForm)
  const [typeFilter, setTypeFilter] = useState('all')
  const [search, setSearch] = useState('')
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')

  async function load() {
    const { data, error } = await supabase.from('v_partners').select('*')
      .eq('company_id', company.id).order('account_no')
    if (error) setError(error.message)
    else setPartners(data)
  }

  useEffect(() => { load() }, [company.id])

  async function create(e) {
    e.preventDefault()
    setError(''); setMessage('')
    // La base de datos valida el NIF, elige o comprueba la subcuenta y crea el tercero
    const { data, error } = await supabase.rpc('create_partner', {
      p_company: company.id,
      p_type: form.type,
      p_name: form.name,
      p_vat_no: form.vat || null,
      p_territory: form.territory,
      p_account_no: form.accountMode === 'existing' ? form.accountNo : null,
      p_email: form.email || null,
    }).single()
    if (error) return setError(error.message)
    if (canSurcharge(form) && form.surcharge) {
      const { error: e2 } = await supabase.from('business_partners').update({ equivalence_surcharge: true }).eq('id', data.partner_id)
      if (e2) setError(e2.message)
    }
    setMessage(t('partnerCreated').replace('{name}', form.name).replace('{n}', data.account_no))
    setForm({ ...emptyForm, type: form.type })
    load()
  }

  const change = (field) => (e) => setForm({ ...form, [field]: e.target.value })

  // Recargo de equivalencia: solo clientes (o deudores) de la Península, y solo si la empresa lleva IVA
  const canSurcharge = (p) => company.tax_territory === 'mainland' && ['customer', 'debtor'].includes(p.type ?? p.partner_type)
    && (p.territory ?? p.tax_territory) === 'mainland'
  async function toggleSurcharge(p) {
    setError('')
    const { error } = await supabase.from('business_partners').update({ equivalence_surcharge: !p.equivalence_surcharge }).eq('id', p.id)
    if (error) return setError(error.message)
    load()
  }

  const q = search.trim().toLowerCase()
  const visible = partners.filter((p) =>
    (typeFilter === 'all' || p.partner_type === typeFilter) &&
    (!q || p.name.toLowerCase().includes(q) || (p.vat_registration_no ?? '').toLowerCase().includes(q) ||
      (p.account_no ?? '').startsWith(q)))

  // Saldo: deudor (nos deben) o acreedor (debemos)
  const balanceText = (b) => {
    const n = Number(b)
    if (!n) return '—'
    return `${money(Math.abs(n), language)} ${n > 0 ? t('debitBalanceShort') : t('creditBalanceShort')}`
  }

  return (
    <>
      {!readOnly && (
        <form onSubmit={create} className="tarjeta">
          <h2>{t('newPartner')}</h2>
          <select value={form.type} onChange={change('type')}>
            {TYPES.map((ty) => <option key={ty} value={ty}>{t(`partnerType.${ty}`)}</option>)}
          </select>
          <p className="ayuda">{t(`partnerTypeHelp.${form.type}`)}</p>
          <input placeholder={t('partnerName')} value={form.name} onChange={change('name')} required />
          <div className="rejilla-cabecera">
            <input placeholder={t('taxId')} value={form.vat} onChange={change('vat')} />
            <select value={form.territory} onChange={change('territory')}>
              {TERRITORIES.map((tt) => <option key={tt} value={tt}>{t(`territory.${tt}`)}</option>)}
            </select>
          </div>
          <input type="email" placeholder={t('emailOptional')} value={form.email} onChange={change('email')} />
          {canSurcharge(form) && (
            <label className="opcion">
              <input type="checkbox" checked={form.surcharge} onChange={(e) => setForm({ ...form, surcharge: e.target.checked })} />
              {t('reCustomer')}
            </label>
          )}

          <div className="opciones">
            <label className="opcion">
              <input type="radio" checked={form.accountMode === 'auto'}
                     onChange={() => setForm({ ...form, accountMode: 'auto' })} />
              {t('accountAuto')}
            </label>
            <label className="opcion">
              <input type="radio" checked={form.accountMode === 'existing'}
                     onChange={() => setForm({ ...form, accountMode: 'existing' })} />
              {t('accountExisting')}
            </label>
          </div>
          {form.accountMode === 'existing' && (
            <input placeholder={t('accountNo')} value={form.accountNo} inputMode="numeric"
                   maxLength={company.posting_account_digits} onChange={change('accountNo')} required />
          )}

          <button type="submit">{t('createPartner')}</button>
          {error && <p className="aviso">⚠ {error}</p>}
          {message && <p className="exito">✓ {message}</p>}
        </form>
      )}

      <section className="tarjeta">
        <h2>{t('partners')} ({visible.length})</h2>
        <nav className="pestanas">
          {['all', ...TYPES].map((ty) => (
            <button key={ty} type="button" className={typeFilter === ty ? 'activa' : ''} onClick={() => setTypeFilter(ty)}>
              {ty === 'all' ? t('all') : t(`partnerTypePlural.${ty}`)}
            </button>
          ))}
        </nav>
        <input placeholder={t('searchPartner')} value={search} onChange={(e) => setSearch(e.target.value)} />
        {visible.length === 0 && <p>{t('noPartners')}</p>}
        <ul>
          {visible.map((p) => (
            <li key={p.id}>
              <strong>
                <span className="codigo">{p.account_no}</span> {p.name}
                {p.equivalence_surcharge && <span className="insignia" title={t('reCustomer')}>RE</span>}
              </strong>
              <span>
                {t(`partnerType.${p.partner_type}`)} · {p.vat_registration_no ?? '—'} · {t(`territory.${p.tax_territory}`)}
                {' · '}{t('balance')}: {balanceText(p.balance)}
              </span>
              {!readOnly && canSurcharge(p) && (
                <label className="opcion pequena">
                  <input type="checkbox" checked={p.equivalence_surcharge} onChange={() => toggleSurcharge(p)} /> {t('reCustomer')}
                </label>
              )}
            </li>
          ))}
        </ul>
      </section>
    </>
  )
}
