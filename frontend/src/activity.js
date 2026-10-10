import { useEffect, useState } from 'react'

// ¿Hay consultas a Supabase en marcha? Un solo contador para TODA la app:
// supabase.js pasa por aquí cada petición (trackedFetch), y las pantallas muestran "Cargando…"
// sin tener que llevar cada una su propio estado de carga.
let pending = 0
const listeners = new Set()
const notify = () => listeners.forEach((fn) => fn(pending))

export async function trackedFetch(...args) {
  pending += 1; notify()
  try {
    return await fetch(...args)
  } finally {
    pending -= 1; notify()
  }
}

// true si hay consultas en marcha desde hace más de `delay` ms (así no parpadea en las rápidas)
export function useBusy(delay = 300) {
  const [busy, setBusy] = useState(false)
  useEffect(() => {
    let timer = null
    const onChange = (n) => {
      clearTimeout(timer)
      if (n > 0) timer = setTimeout(() => setBusy(true), delay)
      else setBusy(false)
    }
    listeners.add(onChange)
    onChange(pending)
    return () => { clearTimeout(timer); listeners.delete(onChange) }
  }, [delay])
  return busy
}
