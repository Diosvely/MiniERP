import { useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import ErrorBox from './ErrorBox'

// CREAR UNA SUBCUENTA SIN SALIR DEL ASIENTO (v0.47.0, mejora de uso 10): la misma alta que el Plan de cuentas
// (erp.create_posting_account, que comprueba los dígitos y que cuelgue de una cuenta del PGC), dentro de Nuevo asiento.
// Al crearla, la línea se queda con la cuenta nueva y se sigue con el importe.
export default function QuickAccount({ company, accountNo, onCreated, onCancel }) {
  const { t } = useI18n()
  const [form, setForm] = useState({ account_no: accountNo ?? '', name: '', name_en: '' })
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  async function create(e) {
    e.preventDefault()
    setBusy(true); setError('')
    const { error: e1 } = await supabase.rpc('create_posting_account', {
      p_company: company.id, p_account_no: form.account_no.trim(), p_name: form.name.trim(), p_name_en: form.name_en.trim() || null,
    })
    setBusy(false)
    if (e1) return setError(e1.message)
    onCreated(form.account_no.trim())
  }

  const change = (field) => (e) => setForm({ ...form, [field]: e.target.value })
  return (
    <form className="cuenta-rapida" onSubmit={create} aria-label={t('qa.title')}>
      <strong>{t('qa.title')}</strong>
      <p className="ayuda">{t('newAccountHelp').replace('{n}', company.posting_account_digits)}</p>
      <div className="rejilla-tres">
        <label>{t('accountNo')}
          <input value={form.account_no} inputMode="numeric" maxLength={company.posting_account_digits} onChange={change('account_no')} required />
        </label>
        <label>{t('accountNameEs')}
          <input value={form.name} onChange={change('name')} required autoFocus />
        </label>
        <label>{t('accountNameEn')}
          <input value={form.name_en} onChange={change('name_en')} />
        </label>
      </div>
      <div className="fila-botones">
        <button type="submit" disabled={busy}>{t('createAccount')}</button>
        <button type="button" className="secundario" onClick={onCancel}>{t('cancel')}</button>
      </div>
      <ErrorBox error={error} company={company} />
    </form>
  )
}
