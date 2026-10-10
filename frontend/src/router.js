import { useEffect, useState } from 'react'

// Rutas con almohadilla (#/…): funcionan en Cloudflare Pages sin configurar nada en el servidor.
//   #/                          → lista de empresas
//   #/empresa/<id>              → la empresa (abre su primera pantalla)
//   #/empresa/<id>/<seccion>    → una pantalla concreta (los id del MENU de CompanyView: balance, journal…)
// El ?demo de la dirección sigue funcionando: va antes de la almohadilla y no se toca.
// Los enlaces de Supabase (#access_token=…) no empiezan por "#/": se tratan como la lista.
export function parseHash(hash = window.location.hash) {
  if (!hash.startsWith('#/')) return []
  return hash.slice(2).split('/').filter(Boolean).map(decodeURIComponent)
}

// Ir a una ruta. replace: true cambia la dirección sin crear un paso más en el botón "atrás"
export function navigate(path, { replace = false } = {}) {
  const hash = `#/${path.replace(/^\/+/, '')}`
  if (window.location.hash === hash) return
  if (replace) {
    window.history.replaceState(null, '', `${window.location.pathname}${window.location.search}${hash}`)
    window.dispatchEvent(new HashChangeEvent('hashchange'))
  } else {
    window.location.hash = hash
  }
}

// Partes de la ruta actual, que se actualizan con los enlaces y con los botones atrás/adelante
export function useHashRoute() {
  const [parts, setParts] = useState(() => parseHash())
  useEffect(() => {
    const onChange = () => setParts(parseHash())
    window.addEventListener('hashchange', onChange)
    return () => window.removeEventListener('hashchange', onChange)
  }, [])
  return parts
}

export const companyPath = (id, section) => `/empresa/${encodeURIComponent(id)}${section ? `/${section}` : ''}`
