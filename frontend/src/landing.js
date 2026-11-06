// v0.59.3 · Portada: enlaces del autor, las secciones y cómo se llega a ellas.
export const REPO = 'https://github.com/Diosvely/MiniERP'
export const LINKEDIN = 'https://www.linkedin.com/in/diosvelyperezarteaga/'
export const YOUTUBE = 'https://www.youtube.com/@DiosvelyPerez'

// Las 6 funciones (texto en i18n: landingFeature.<clave>) y los puntos de «¿Por qué MiniERP?» (landingWhy.<clave>)
export const FEATURES = ['accounting', 'reports', 'dashboards', 'ai', 'trace', 'import']
export const WHY = ['doing', 'practice', 'auditor', 'norm', 'open']

// Ir a una sección de la portada SIN tocar el hash: la web enruta con #/… (router.js), y un href="#acceso" cambiaría
// de ruta. Lleva el foco al primer campo (o, si no hay, al primer botón) de la sección, para quien navega con teclado.
export function scrollToSection(id, doc = globalThis.document) {
  const el = doc?.getElementById(id)
  if (!el) return false
  el.scrollIntoView?.({ behavior: 'smooth', block: 'start' })
  const target = el.querySelector?.('input') ?? el.querySelector?.('button')   // el correo antes que las pestañas
  target?.focus?.({ preventScroll: true })
  return true
}
