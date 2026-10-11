// Utilidades de los gráficos (dibujados a mano en SVG)

// Marcas "redondas" del eje: unos 3 valores bonitos que cubren el rango (p. ej. 0 · 25.000 · 50.000).
// El gráfico de tesorería empieza siempre en 0 (lleva área debajo): cortar el eje exageraría las subidas y bajadas.
export function niceTicks(min, max) {
  const span = Math.max(max - min, 1)
  const raw = span / 2
  const pow = 10 ** Math.floor(Math.log10(raw))
  const step = [1, 2, 2.5, 5, 10].map((m) => m * pow).find((s) => s >= raw) ?? 10 * pow
  const lo = Math.floor(min / step) * step
  const hi = Math.ceil(max / step) * step
  const ticks = []
  for (let v = lo; v <= hi + step / 2; v += step) ticks.push(v)
  if (ticks.length < 2) ticks.push(lo + step)   // todo a cero: al menos un tramo
  return ticks
}
