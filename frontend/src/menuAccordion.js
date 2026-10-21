// MENÚ EN ACORDEÓN (v0.41.1): en el modo Auditor solo se ve el título de cada área (Contabilidad, Facturas,
// Impuestos, Informes, Datos maestros, Empresa) y una sola abierta a la vez, como el panel de navegación de BC.

// Al pulsar el título de un área: si estaba abierta se cierra; si no, se abre ella sola (las demás se cierran)
export const toggleGroup = (open, clicked) => (open === clicked ? null : clicked)

// El área que se abre al entrar en una pantalla: la suya (el Inicio no tiene área: se deja la que hubiera abierta)
export const groupForSection = (group, current) => (group ? group : current)

// Flechas ↑ ↓ dentro del menú: el botón siguiente o el anterior (dando la vuelta), sin salir del menú
export function nextIndex(index, total, key) {
  if (!total) return -1
  if (key === 'ArrowDown') return (index + 1) % total
  if (key === 'ArrowUp') return (index - 1 + total) % total
  if (key === 'Home') return 0
  if (key === 'End') return total - 1
  return index
}
