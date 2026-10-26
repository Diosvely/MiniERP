import { useEffect, useRef } from 'react'
import { supabase } from '../supabase'
import { HEARTBEAT_MS, TEMP_CHANGED, leaveRequest } from '../temporary'

// LATIDO DE LAS EMPRESAS TEMPORALES (v0.49.0): no se pinta nada. Mientras la app está abierta, cada 5 minutos (y al
// volver a la pestaña) mantiene vivas las empresas temporales del usuario; al cerrar la pestaña, avisa para que se
// borren en unos 10 minutos. Si el aviso no llega (móvil, batería…), la base de datos las borra tras 2 h sin latido.
export default function TempKeeper({ session }) {
  const token = useRef(null)
  const hasTemp = useRef(false)
  useEffect(() => { token.current = session?.access_token ?? null }, [session?.access_token])

  useEffect(() => {
    if (!session || session.user?.is_anonymous) return
    let alive = true
    const beat = () => supabase.rpc('temp_heartbeat').then(({ data, error }) => {
      if (alive && !error) hasTemp.current = Number(data) > 0
    })
    const onVisible = () => { if (document.visibilityState === 'visible') beat() }
    const onLeave = () => {
      if (!hasTemp.current || !token.current) return
      try { fetch(...leaveRequest(import.meta.env.VITE_SUPABASE_URL, import.meta.env.VITE_SUPABASE_KEY, token.current)) } catch { /* se encarga la limpieza */ }
    }
    beat()
    const id = setInterval(beat, HEARTBEAT_MS)
    document.addEventListener('visibilitychange', onVisible)
    window.addEventListener('pagehide', onLeave)
    window.addEventListener(TEMP_CHANGED, beat)   // al terminar una importación temporal
    return () => {
      alive = false
      clearInterval(id)
      document.removeEventListener('visibilitychange', onVisible)
      window.removeEventListener('pagehide', onLeave)
      window.removeEventListener(TEMP_CHANGED, beat)
    }
  }, [session?.user?.id])   // eslint-disable-line react-hooks/exhaustive-deps

  return null
}
