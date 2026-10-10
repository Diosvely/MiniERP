import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { accountName } from '../format'
import ErrorBox from './ErrorBox'

const rateText = (n, language) => `${Number(n).toLocaleString(language === 'en' ? 'en-GB' : 'es-ES')} %`

// Configuración de impuestos: qué subcuenta usa cada tipo de IVA/IGIC
// (como "VAT Posting Setup" de Business Central o la OB40 de SAP)
export default function Taxes({ company, readOnly, onChanged }) {
  const { t, language } = useI18n()
  const canEdit = !readOnly && company.my_role === 'admin'
  const [setup, setSetup] = useState([])
  const [settlement, setSettlement] = useState([])
  const [accounts, setAccounts] = useState([])
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)

  async function load() {
    const [s, l, a] = await Promise.all([
      supabase.from('v_tax_setup').select('*').eq('company_id', company.id).order('tax_type').order('rate_pct'),
      supabase.from('v_tax_settlement_setup').select('*').eq('company_id', company.id).order('tax_type'),
      // Solo subcuentas del grupo 47: son las únicas que admite la configuración
      supabase.from('gl_accounts').select('id, account_no, name, name_en')
        .eq('company_id', company.id).eq('account_type', 'posting').like('account_no', '47%').order('account_no'),
    ])
    const failed = s.error || l.error || a.error
    if (failed) return setError(failed.message)
    setSetup(s.data); setSettlement(l.data); setAccounts(a.data)
  }

  useEffect(() => { load() }, [company.id])

  // Asistente: crea las subcuentas 472/477 de cada tipo y las de la liquidación (4750/4700)
  async function runAssistant(taxType) {
    setError(''); setMessage(''); setBusy(true)
    const { data, error } = await supabase.rpc('setup_taxes', { p_company: company.id, p_tax_type: taxType })
    setBusy(false)
    if (error) return setError(error.message)
    const created = data.filter((r) => r.status === 'created').length
    const linked = data.filter((r) => r.status === 'linked').length
    setMessage(t('taxAssistantDone').replace('{created}', created).replace('{linked}', linked))
    load()
  }

  // Cambiar una cuenta o bloquear un tipo: la base de datos valida que sea 472 / 477
  async function updateSetup(row, changes) {
    setError(''); setMessage('')
    const { error } = await supabase.from('tax_setup').update(changes)
      .eq('company_id', company.id).eq('tax_code', row.tax_code)
    if (error) return setError(error.message)
    load()
  }

  async function updateSettlement(row, changes) {
    setError(''); setMessage('')
    const { error } = await supabase.from('tax_settlement_setup').update(changes)
      .eq('company_id', company.id).eq('tax_type', row.tax_type)
    if (error) return setError(error.message)
    load()
  }

  // Régimen de IVA: general o recargo de equivalencia (comerciante minorista, solo en la Península)
  async function changeRegime(regime) {
    setError(''); setMessage('')
    const { error } = await supabase.rpc('set_vat_regime', { p_company: company.id, p_regime: regime })
    if (error) return setError(error.message)
    onChanged?.({ ...company, vat_regime: regime })
  }

  const options = (prefix) => accounts.filter((a) => a.account_no.startsWith(prefix))

  // Selector de cuenta (admin) o número y nombre (resto)
  function AccountField({ label, id, no, name, prefix, onChange, allowEmpty }) {
    return (
      <label>{label}
        {canEdit ? (
          <select value={id ?? ''} onChange={(e) => onChange(e.target.value || null)}>
            {(allowEmpty || !id) && <option value="">—</option>}
            {options(prefix).map((a) => (
              <option key={a.id} value={a.id}>{a.account_no} · {accountName(a, language)}</option>
            ))}
          </select>
        ) : (
          <span>{no ? <><span className="codigo">{no}</span>{name}</> : '—'}</span>
        )}
      </label>
    )
  }

  const homeTax = company.tax_territory === 'canary_islands' ? 'IGIC' : 'VAT'
  const otherTax = homeTax === 'IGIC' ? 'VAT' : 'IGIC'
  const configured = (type) => setup.some((r) => r.tax_type === type)

  return (
    <>
      <section className="tarjeta">
        <h2>{t('taxSetup')}</h2>
        <p className="ayuda">{t('taxSetupHelp')}</p>
        {canEdit && (
          <div className="fila">
            {!configured(homeTax) && (
              <button type="button" disabled={busy} onClick={() => runAssistant(homeTax)}>
                {t('taxAssistant').replace('{tax}', t(`taxType.${homeTax}`))}
              </button>
            )}
            {!configured(otherTax) && (
              <button type="button" className="secundario" disabled={busy} onClick={() => runAssistant(otherTax)}>
                {t('taxAssistantOther').replace('{tax}', t(`taxType.${otherTax}`))}
              </button>
            )}
          </div>
        )}
        {company.tax_territory === 'mainland' && (
          <label className="regimen">{t('vatRegime')}
            {canEdit ? (
              <select value={company.vat_regime ?? 'general'} onChange={(e) => changeRegime(e.target.value)}>
                {['general', 'equivalence_surcharge'].map((r) => <option key={r} value={r}>{t(`vatRegimes.${r}`)}</option>)}
              </select>
            ) : <strong>{t(`vatRegimes.${company.vat_regime ?? 'general'}`)}</strong>}
            <span className="ayuda">{t('vatRegimeHelp')}</span>
          </label>
        )}
        {!canEdit && !readOnly && <p className="ayuda">{t('taxAdminOnly')}</p>}
        {setup.length === 0 && <p>{t('noTaxSetup')}</p>}
        <ErrorBox error={error} company={company} />
        {message && <p className="exito">✓ {message}</p>}
      </section>

      {['IGIC', 'VAT'].filter(configured).map((type) => (
        <section key={type} className="tarjeta">
          <h2>{t(`taxType.${type}`)}</h2>
          <ul className="impuestos">
            {setup.filter((r) => r.tax_type === type).map((r) => (
              <li key={r.tax_code} className={r.blocked ? 'bloqueado' : ''}>
                <strong>
                  {rateText(r.rate_pct, language)} · {language === 'en' ? r.description_en : r.description}
                  <span className="codigo"> {r.tax_code}</span>
                </strong>
                {Number(r.rate_pct) === 0 ? (
                  <span className="ayuda">{t('noTaxAmount')}</span>
                ) : (
                  <div className="rejilla-cabecera">
                    <AccountField label={t('inputTax')} id={r.input_account_id} no={r.input_account_no}
                                  name={r.input_account_name} prefix="472" allowEmpty={r.blocked}
                                  onChange={(v) => updateSetup(r, { input_account_id: v })} />
                    <AccountField label={t('outputTax')} id={r.output_account_id} no={r.output_account_no}
                                  name={r.output_account_name} prefix="477" allowEmpty={r.blocked}
                                  onChange={(v) => updateSetup(r, { output_account_id: v })} />
                    {r.equivalence_surcharge_pct != null && (
                      <AccountField label={`${t('surchargeAccount')} ${rateText(r.equivalence_surcharge_pct, language)}`}
                                    id={r.surcharge_account_id} no={r.surcharge_account_no}
                                    name={r.surcharge_account_name} prefix="477" allowEmpty={r.blocked}
                                    onChange={(v) => updateSetup(r, { surcharge_account_id: v })} />
                    )}
                  </div>
                )}
                {canEdit && (
                  <label className="opcion">
                    <input type="checkbox" checked={r.blocked}
                           onChange={(e) => updateSetup(r, { blocked: e.target.checked })} />
                    {t('taxBlocked')}
                  </label>
                )}
                {!canEdit && r.blocked && <span className="ayuda">{t('taxBlocked')}</span>}
              </li>
            ))}
          </ul>

          {settlement.filter((s) => s.tax_type === type).map((s) => (
            <div key={s.tax_type} className="liquidacion">
              <h3>{t('taxSettlement')}</h3>
              <p className="ayuda">{t('taxSettlementHelp')}</p>
              <div className="rejilla-cabecera">
                <AccountField label={t('taxPayable')} id={s.payable_account_id} no={s.payable_account_no}
                              name={s.payable_account_name} prefix="4750"
                              onChange={(v) => updateSettlement(s, { payable_account_id: v })} />
                <AccountField label={t('taxReceivable')} id={s.receivable_account_id} no={s.receivable_account_no}
                              name={s.receivable_account_name} prefix="4700"
                              onChange={(v) => updateSettlement(s, { receivable_account_id: v })} />
              </div>
            </div>
          ))}
        </section>
      ))}
    </>
  )
}
