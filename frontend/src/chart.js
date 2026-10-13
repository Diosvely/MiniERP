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

// Tramos de una cascada: del saldo inicial al final pasando por cada flujo.
//   start: saldo inicial · steps: [{ key, value }] · → [{ key, from, to, kind: 'total' | 'up' | 'down' }]
// Cada flujo empieza donde acabó el anterior; el último tramo es el saldo final (de 0 al resultado).
export function waterfall(start, steps) {
  const bars = [{ key: 'start', from: 0, to: Number(start), kind: 'total' }]
  let acc = Number(start)
  for (const s of steps) {
    const v = Number(s.value)
    bars.push({ key: s.key, from: acc, to: acc + v, kind: v >= 0 ? 'up' : 'down' })
    acc += v
  }
  bars.push({ key: 'end', from: 0, to: acc, kind: 'total' })
  return bars
}

// Barra con las esquinas de ARRIBA redondeadas (radio r) y la base recta, apoyada en el eje: x, y = esquina superior
export function barPath(x, y, w, h, r = 4) {
  const rr = Math.max(0, Math.min(r, w / 2, h))
  return `M${x},${y + h}V${y + rr}Q${x},${y} ${x + rr},${y}H${x + w - rr}Q${x + w},${y} ${x + w},${y + rr}V${y + h}Z`
}
