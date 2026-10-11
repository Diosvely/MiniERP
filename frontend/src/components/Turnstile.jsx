import { useEffect, useRef } from 'react'

// CAPTCHA de Cloudflare Turnstile (gratis y sin "pasos de semáforos": casi siempre se resuelve solo).
// Supabase lo exige, una vez activado, para entrar como invitado, registrarse e iniciar sesión.
// Cada token vale UNA vez: tras cada intento se cambia resetKey y el widget pide otro.
// Sin VITE_TURNSTILE_SITE_KEY (desarrollo, o antes de configurarlo) no se pinta nada y la web funciona igual.
export const CAPTCHA_KEY = import.meta.env.VITE_TURNSTILE_SITE_KEY || ''
const SRC = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit'

let loading = null
function loadTurnstile() {
  if (window.turnstile) return Promise.resolve(window.turnstile)
  loading ??= new Promise((resolve, reject) => {
    const s = document.createElement('script')
    s.src = SRC
    s.async = true
    s.onload = () => resolve(window.turnstile)
    s.onerror = () => { loading = null; reject(new Error('turnstile')) }
    document.head.appendChild(s)
  })
  return loading
}

export default function Turnstile({ onToken, resetKey = 0, language = 'es' }) {
  const box = useRef(null)
  const widget = useRef(null)
  const callback = useRef(onToken)
  useEffect(() => { callback.current = onToken })

  // Pintar el widget (y repintarlo si cambia el idioma)
  useEffect(() => {
    if (!CAPTCHA_KEY) return
    let alive = true
    loadTurnstile().then((ts) => {
      if (!alive || !box.current) return
      widget.current = ts.render(box.current, {
        sitekey: CAPTCHA_KEY,
        language,
        callback: (token) => callback.current(token),
        'expired-callback': () => callback.current(null),
        'error-callback': () => callback.current(null),
      })
    }).catch(() => callback.current(null))
    return () => {
      alive = false
      if (widget.current != null) window.turnstile?.remove(widget.current)
      widget.current = null
    }
  }, [language])

  // Token gastado: se pide uno nuevo
  useEffect(() => {
    if (resetKey && widget.current != null) {
      callback.current(null)
      window.turnstile?.reset(widget.current)
    }
  }, [resetKey])

  if (!CAPTCHA_KEY) return null
  return <div ref={box} className="captcha" />
}
