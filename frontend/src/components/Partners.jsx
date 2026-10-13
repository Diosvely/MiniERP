import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { money } from '../format'
import ErrorBox from './ErrorBox'
import { allowedWithholdings, canWithhold, legalFormFromTaxId } from '../partnerTax'

const TYPES = ['customer', 'vendor', 'creditor', 'debtor']
const TERRITORIES = ['canary_islands', 'mainland', 'ceuta_melilla', 'eu', 'non_eu']

// Terceros: clientes, proveedores, acreedores y deudores, cada uno con su subcuenta
export default function Partners({ company, readOnly }) {
  const { t, language } = useI18n()
  const emptyForm = {
    type: 'customer', name: '', vat: '', territory: company.tax_territory,
    accountMode: 'auto', accountNo: '', email: '', surcharge: false, legalForm: '', withholding: '',
  }
  const [partners, setPartners] = useState([])
  const [whCodes, setWhCodes] = useState([])
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
  // Catálogo de retenciones (IRPF15, IRPF7, IRPF19), común a todas las empresas
  useEffect(() => {
    supabase.from('withholding_codes').select('code, kind, rate_pct, description, description_en').order('code')
      .then(({ data }) => setWhCodes(data ?? []))
  }, [])

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
    // Datos que no van en el alta: recargo de equivalencia, forma jurídica y retención por defecto
    const extra = {}
    if (canSurcharge(form) && form.surcharge) extra.equivalence_surcharge = true
    if (canWithhold(form.type) && form.legalForm) extra.legal_form = form.legalForm
    if (canWithhold(form.type) && formCodes.some((c) => c.code === form.withholding)) extra.withholding_code = form.withholding
    if (Object.keys(extra).length) {
      const { error: e2 } = await supabase.from('business_partners').update(extra).eq('id', data.partner_id)
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

  // Retención por defecto: la ficha del tercero manda en las facturas y en el Tutor IA
  async function changeWithholding(p, code) {
    setError('')
    const { error } = await supabase.from('business_partners').update({ withholding_code: code || null }).eq('id', p.id)
    if (error) return setError(error.message)
    load()
  }
  const whLabel = (c) => `${c.code} · ${language === 'en' ? c.description_en : c.description}`
  // Forma jurídica del formulario: la elegida o la que dice el NIF
  const formLegal = form.legalForm || legalFormFromTaxId(form.vat)
  const formCodes = allowedWithholdings(whCodes, form.type, formLegal)

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
          <select value={form.type} onChange={change('type')} aria-label={t('partnerTypeField')}>
            {TYPES.map((ty) => <option key={ty} value={ty}>{t(`partnerType.${ty}`)}</option>)}
          </select>
          <p className="ayuda">{t(`partnerTypeHelp.${form.type}`)}</p>
          <input placeholder={t('partnerName')} value={form.name} onChange={change('name')} required />
          <div className="rejilla-cabecera">
            <input placeholder={t('taxId')} value={form.vat} onChange={change('vat')} />
            <select value={form.territory} onChange={change('territory')} aria-label={t('territoryLabel')}>
              {TERRITORIES.map((tt) => <option key={tt} value={tt}>{t(`territory.${tt}`)}</option>)}
            </select>
          </div>
          <input type="email" placeholder={t('emailOptional')} value={form.email} onChange={change('email')} />
          {canWithhold(form.type) && (
            <div className="rejilla-cabecera ficha-fiscal">
              <label>{t('legalForm')}
                <select value={form.legalForm} onChange={(e) => setForm({ ...form, legalForm: e.target.value, withholding: '' })}>
                  <option value="">{t('legalFormAuto')}{legalFormFromTaxId(form.vat) ? `: ${t(`legalFormName.${legalFormFromTaxId(form.vat)}`)}` : ''}</option>
                  <option value="individual">{t('legalFormName.individual')}</option>
                  <option value="company">{t('legalFormName.company')}</option>
                </select>
              </label>
              <label>{t('defaultWithholding')}
                <select value={formCodes.some((c) => c.code === form.withholding) ? form.withholding : ''} onChange={change('withholding')}>
                  <option value="">{t('noWithholding')}</option>
                  {formCodes.map((c) => <option key={c.code} value={c.code}>{whLabel(c)}</option>)}
                </select>
              </label>
            </div>
          )}
          {canWithhold(form.type) && <p className="ayuda">{t('defaultWithholdingHelp')}</p>}
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
          <ErrorBox error={error} company={company} />
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
                {p.legal_form && <>{' · '}{t(`legalFormName.${p.legal_form}`)}</>}
                {' · '}{t('balance')}: {balanceText(p.balance)}
              </span>
              {canWithhold(p.partner_type) && (readOnly
                ? p.withholding_code && <span className="insignia">{p.withholding_code}</span>
                : (
                  <label className="retencion-tercero">{t('defaultWithholding')}
                    <select value={p.withholding_code ?? ''} onChange={(e) => changeWithholding(p, e.target.value)}>
                      <option value="">{t('noWithholding')}</option>
                      {allowedWithholdings(whCodes, p.partner_type, p.legal_form).map((c) => <option key={c.code} value={c.code}>{whLabel(c)}</option>)}
                    </select>
                  </label>
                ))}
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
