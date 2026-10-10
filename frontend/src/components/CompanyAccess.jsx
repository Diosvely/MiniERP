import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { money } from '../format'
import ErrorBox from './ErrorBox'

// ACCESOS (solo el propietario de la aplicación): quién entra en esta empresa y con qué rol,
// quién es el TITULAR DE LOS DATOS (Miembro) y las opiniones sobre la IA que han dejado.
export default function CompanyAccess({ company }) {
  const { t, language } = useI18n()
  const [rows, setRows] = useState([])
  const [feedback, setFeedback] = useState([])
  const [form, setForm] = useState({ email: '', role: 'accountant', data_owner: true })
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [open, setOpen] = useState({})

  async function load() {
    const [a, f] = await Promise.all([
      supabase.rpc('company_access', { p_company: company.id }),
      supabase.from('ai_feedback').select('*').eq('company_id', company.id).order('created_at', { ascending: false }),
    ])
    if (a.error) return setError(a.error.message)
    setRows(a.data)
    setFeedback(f.data ?? [])
  }
  useEffect(() => { load() }, [company.id])

  async function add(e) {
    e.preventDefault()
    setError(''); setMessage(''); setBusy(true)
    const { error } = await supabase.rpc('grant_company_access', {
      p_company: company.id, p_email: form.email, p_role: form.role, p_data_owner: form.data_owner,
    })
    setBusy(false)
    if (error) return setError(/no registered user/i.test(error.message) ? t('accessUserNotFound') : error.message)
    setMessage(t('accessAdded').replace('{e}', form.email.trim()))
    setForm({ ...form, email: '' })
    load()
  }

  async function revoke(r) {
    setError(''); setMessage('')
    const { error } = await supabase.rpc('revoke_company_access', { p_company: company.id, p_user: r.user_id })
    if (error) return setError(error.message)
    setMessage(t('accessRevoked').replace('{e}', r.email))
    load()
  }

  const emailOf = (id) => rows.find((r) => r.user_id === id)?.email ?? t('accessYou')
  const date = (d) => new Date(d).toLocaleDateString(language === 'en' ? 'en-GB' : 'es-ES')
  const icon = { correct: '👍', partial: '◐', wrong: '👎' }

  return (
    <>
      <section className="tarjeta">
        <h2>{t('accessTitle')}</h2>
        <p className="ayuda">{t('accessIntro')}</p>
        <ul className="accesos">
          {rows.map((r) => (
            <li key={r.user_id}>
              <div>
                <strong>{r.email}</strong>
                <span className="ayuda">
                  {t(`companyRole.${r.role}`)}
                  {r.data_owner && <span className="insignia">{t('accessDataOwnerBadge')}</span>}
                  {' · '}{t('accessSince')} {date(r.since)}
                  {r.ai_calls_today > 0 && ` · ${t('accessAiToday').replace('{n}', r.ai_calls_today)}`}
                </span>
              </div>
              {r.role !== 'admin' && (
                <button type="button" className="secundario" onClick={() => revoke(r)}>{t('accessRevoke')}</button>
              )}
            </li>
          ))}
        </ul>

        <form onSubmit={add} className="alta-acceso">
          <h3>{t('accessAddTitle')}</h3>
          <input type="email" required placeholder={t('accessEmail')} value={form.email}
                 onChange={(e) => setForm({ ...form, email: e.target.value })} />
          <select value={form.role} onChange={(e) => setForm({ ...form, role: e.target.value })}>
            {['accountant', 'viewer', 'admin'].map((r) => <option key={r} value={r}>{t(`companyRole.${r}`)}</option>)}
          </select>
          <label className="opcion">
            <input type="checkbox" checked={form.data_owner} onChange={(e) => setForm({ ...form, data_owner: e.target.checked })} />
            {t('accessDataOwner')}
          </label>
          <p className="ayuda">{t('accessDataOwnerHelp')}</p>
          <button type="submit" disabled={busy || !form.email.trim()}>{t('accessAdd')}</button>
        </form>
        <p className="ayuda">{t('accessHowTo')}</p>
        <ErrorBox error={error} company={company} />
        {message && <p className="exito">✓ {message}</p>}
      </section>

      <section className="tarjeta">
        <h2>{t('feedbackTitle')}</h2>
        <p className="ayuda">{t('feedbackIntro')}</p>
        {feedback.length === 0 && <p>{t('feedbackNone')}</p>}
        <ul className="opiniones">
          {feedback.map((f) => (
            <li key={f.id} className={f.verdict}>
              <div className="cabecera-opinion">
                <strong>{icon[f.verdict]} {t(`verdict.${f.verdict}`)}</strong>
                <span className="ayuda">
                  {t(`feedbackKind.${f.kind}`)} · {emailOf(f.user_id)} · {date(f.created_at)}{f.model && ` · ${f.model.replace(/^@cf\//, '')}`}
                </span>
              </div>
              {f.prompt && <p className="concepto">“{f.prompt}”</p>}
              {f.comment && <p>💬 {f.comment}</p>}
              <button type="button" className="enlace" onClick={() => setOpen({ ...open, [f.id]: !open[f.id] })}>
                {open[f.id] ? '▾' : '▸'} {t('feedbackShowAnswer')}
              </button>
              {open[f.id] && (f.answer?.lines?.length ? (
                <table className="informe">
                  <tbody>
                    {f.answer.lines.map((l, i) => (
                      <tr key={i}>
                        <td><span className="codigo">{l.account_no}</span> {l.account_name}</td>
                        <td className="num">{Number(l.debit) ? money(l.debit, language) : ''}</td>
                        <td className="num">{Number(l.credit) ? money(l.credit, language) : ''}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              ) : (
                <pre className="ia-texto">{JSON.stringify(f.answer, null, 2)}</pre>
              ))}
            </li>
          ))}
        </ul>
      </section>
    </>
  )
}
