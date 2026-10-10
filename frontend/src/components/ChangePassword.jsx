import { useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'

// Cambiar la contraseña del usuario conectado (los Miembros entran con una provisional que les da el owner)
export default function ChangePassword({ onDone }) {
  const { t } = useI18n()
  const [pass, setPass] = useState('')
  const [repeat, setRepeat] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [done, setDone] = useState(false)

  async function save(e) {
    e.preventDefault()
    setError('')
    if (pass.length < 8) return setError(t('passwordShort'))
    if (pass !== repeat) return setError(t('passwordMismatch'))
    setBusy(true)
    const { error } = await supabase.auth.updateUser({ password: pass })
    setBusy(false)
    if (error) return setError(error.message)
    setDone(true)
    setPass(''); setRepeat('')
  }

  return (
    <form className="tarjeta" onSubmit={save}>
      <h2>🔑 {t('changePassword')}</h2>
      {done ? (
        <>
          <p className="exito">✓ {t('passwordChanged')}</p>
          <button type="button" className="secundario" onClick={onDone}>{t('close')}</button>
        </>
      ) : (
        <>
          <input type="password" autoComplete="new-password" placeholder={t('newPassword')} value={pass}
                 onChange={(e) => setPass(e.target.value)} />
          <input type="password" autoComplete="new-password" placeholder={t('repeatPassword')} value={repeat}
                 onChange={(e) => setRepeat(e.target.value)} />
          <div className="fila">
            <button type="button" className="secundario" onClick={onDone}>{t('cancel')}</button>
            <button type="submit" disabled={busy || !pass}>{t('savePassword')}</button>
          </div>
          {error && <p className="aviso">⚠ {error}</p>}
        </>
      )}
    </form>
  )
}
