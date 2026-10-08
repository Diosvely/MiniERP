import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'

// Analista IA (Cloudflare Workers AI, modelo open source): interpreta los estados, el EFE y los ratios ya calculados.
// Solo lo ve el propietario de la aplicación (erp.can_use_ai). La IA no contabiliza ni cambia nada.
export default function AiAnalyst({ company, year }) {
  const { t, language } = useI18n()
  const [allowed, setAllowed] = useState(false)
  const [result, setResult] = useState(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    supabase.rpc('can_use_ai').then(({ data }) => setAllowed(data === true))
  }, [])

  // Otro año u otra empresa: el análisis anterior ya no vale
  useEffect(() => { setResult(null); setError('') }, [company.id, year])

  async function analyse() {
    setBusy(true); setError(''); setResult(null)
    try {
      const { data: { session } } = await supabase.auth.getSession()
      const res = await fetch('/api/ai', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${session?.access_token ?? ''}` },
        body: JSON.stringify({ company_id: company.id, year: Number(year), language }),
      })
      // En "npm run dev" no hay Pages Functions: la ruta no existe
      if (res.status === 404 || !(res.headers.get('content-type') ?? '').includes('json')) {
        throw new Error(t('aiNotAvailableLocally'))
      }
      const body = await res.json()
      if (!res.ok) throw new Error(t(`aiError.${body.error}`) + (body.detail ? ` (${body.detail})` : ''))
      setResult(body)
    } catch (e) {
      setError(e.message)
    } finally {
      setBusy(false)
    }
  }

  if (!allowed) return null
  const a = result?.analysis

  return (
    <section className="tarjeta analista-ia">
      <h2>🤖 {t('aiTitle')} · {year}</h2>
      <p className="ayuda">{t('aiIntro')}</p>
      <button type="button" disabled={busy} onClick={analyse}>
        {busy ? `${t('aiThinking')}…` : result ? t('aiAgain') : t('aiAnalyse')}
      </button>
      {busy && <p className="ayuda">{t('aiWait')}</p>}
      {error && <p className="aviso">⚠ {error}</p>}

      {a && (
        <div className="analisis">
          <p className="resumen-ia">{a.summary}</p>
          {[
            ['strengths', '✓', 'aiStrengths'],
            ['alerts', '⚠', 'aiAlerts'],
            ['auditor_questions', '?', 'aiQuestions'],
          ].map(([key, icon, label]) => a[key].length > 0 && (
            <div key={key} className={`bloque-ia ${key}`}>
              <h3>{t(label)}</h3>
              <ul>{a[key].map((x, i) => <li key={i}><span className="icono">{icon}</span> {x}</li>)}</ul>
            </div>
          ))}
          {a.learning && (
            <div className="bloque-ia learning">
              <h3>💡 {t('aiLearning')}</h3>
              <p>{a.learning}</p>
            </div>
          )}
        </div>
      )}
      {result && !a && result.raw && <pre className="ia-texto">{result.raw}</pre>}
      {result && <p className="ayuda">{t('aiDisclaimer').replace('{m}', result.model.replace(/^@cf\//, ''))}</p>}
    </section>
  )
}
