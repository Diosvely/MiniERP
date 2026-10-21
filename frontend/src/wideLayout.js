// PANTALLA ANCHA (v0.41.1): en el PC (≥ 1320 px) dos tarjetas seguidas sin tabla van una al lado de la otra.
// La regla vive aquí y no en el CSS porque el CSS no sabe preguntar «¿la siguiente también es pequeña?»
// (:has() no se puede anidar). Así nunca queda una tarjeta sola a media anchura con un hueco al lado.

// Lo que hace ancha a una tarjeta: una tabla, un gráfico, los indicadores, las líneas de un asiento o los pasos del cierre
export const WIDE_CONTENT = 'table, svg, .kpis, .lineas, .pasos-cierre, .linea, .inicio'

// halves: [true, true, false, true, true, true] → cuáles van a media anchura: [true, true, false, true, true, false]
// De izquierda a derecha y por parejas: una pequeña sin pareja se queda a todo el ancho.
export function pairHalves(halves) {
  const out = halves.map(() => false)
  for (let i = 0; i < halves.length - 1; i++) {
    if (halves[i] && halves[i + 1]) { out[i] = true; out[i + 1] = true; i++ }
  }
  return out
}

// Marca con la clase «mitad» los hijos de la zona de contenido que van emparejados
export function markHalves(container) {
  if (!container) return
  const kids = [...container.children]
  const halves = kids.map((el) => el.classList.contains('tarjeta') && !el.querySelector(WIDE_CONTENT))
  pairHalves(halves).forEach((half, i) => kids[i].classList.toggle('mitad', half))
}
