import { useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'

// "¿Es correcta esta respuesta de la IA?" — la opinión se guarda en erp.ai_feedback y el owner la lee en Accesos.
// Sirve para que quien sabe contabilidad (los Miembros) diga dónde se equivoca la IA y así mejorarla.
export default function AiFeedback({ company, kind, prompt, answer, model }) {
  const { t } = useI18n()
  const [verdict, setVerdict] = useState('')
  const [comment, setComment] = useState('')
  const [sent, setSent] = useState(false)
  const [error, setError] = useState('')

  async function send() {
    setError('')
    const { error } = await supabase.from('ai_feedback').insert({
      company_id: company.id, kind, prompt: prompt || null, answer, verdict,
      comment: comment.trim() || null, model,
    })
    if (error) return setError(error.message)
    setSent(true)
  }

  if (sent) return <p className="exito">✓ {t('feedbackThanks')}</p>

  return (
    <div className="opinion-ia">
      <span>{t('feedbackAsk')}</span>
      <div className="fila-opiniones">
        {[['correct', '👍'], ['partial', '◐'], ['wrong', '👎']].map(([v, icon]) => (
          <button key={v} type="button" className={verdict === v ? 'activa' : 'secundario'} onClick={() => setVerdict(v)}>
            {icon} {t(`verdict.${v}`)}
          </button>
        ))}
      </div>
      {verdict && (
        <>
          <textarea rows={2} maxLength={2000} value={comment} onChange={(e) => setComment(e.target.value)}
                    placeholder={verdict === 'correct' ? t('feedbackCommentOptional') : t('feedbackCommentWrong')} />
          <button type="button" onClick={send}>{t('feedbackSend')}</button>
        </>
      )}
      {error && <p className="aviso">⚠ {error}</p>}
    </div>
  )
}
