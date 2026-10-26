// EMPRESAS TEMPORALES (v0.49.0, migración 0072): un registrado importa su diario en una empresa de prueba que se borra
// sola tras 2 h sin usar la aplicación o, como muy tarde, a las 48 h. Aquí, lo que no es pantalla (se prueba en
// tests/temporary.test.js): el latido, el aviso al cerrar la pestaña y qué enseñar en «Importar».

// Mientras la app está abierta, cada 5 minutos se le dice a la base de datos «sigo aquí» (erp.temp_heartbeat)
export const HEARTBEAT_MS = 5 * 60 * 1000
// Aviso dentro de la página: «hay una empresa temporal nueva» (el latido empieza a contar con ella)
export const TEMP_CHANGED = 'erp-temp-changed'

// «2 h» · «90 min»
export const idleText = (minutes) => (minutes % 60 === 0 ? `${minutes / 60} h` : `${minutes} min`)

// Fecha y hora cortas: «28/10, 21:30»
export const shortDateTime = (iso, language) => new Date(iso).toLocaleString(language === 'en' ? 'en-GB' : 'es-ES',
  { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })

// Qué enseña la tarjeta «Importar» según erp.temp_status (null: sin la migración 0072, como antes)
//   'permanent' → como siempre (si le quedan empresas) · 'temporary' → en temporal, si no tiene ya una y no está lleno
export function importCard(status, canCreate) {
  if (!status || status.mode === 'permanent') return { show: Boolean(canCreate), temporary: false }
  if (status.mode !== 'temporary') return { show: false, temporary: false }
  if (status.company) return { show: true, temporary: true, blocked: 'hasTemp' }
  if (status.full) return { show: true, temporary: true, blocked: 'full' }
  return { show: true, temporary: true, blocked: null }
}

// ¿Cabe el fichero en una empresa temporal?
export const tooManyLines = (status, rows) => Boolean(status?.mode === 'temporary' && rows > status.max_lines_per_import)

// Al cerrar la pestaña: erp.temp_leave con fetch «keepalive» (llega aunque la página se esté cerrando).
// La caducidad se adelanta a unos 10 minutos; si hay otra pestaña abierta, su latido la mantiene viva.
export function leaveRequest(url, key, token) {
  return [`${url}/rest/v1/rpc/temp_leave`, {
    method: 'POST', keepalive: true, body: '{}',
    headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json',
               'Content-Profile': 'erp', 'Accept-Profile': 'erp' },
  }]
}
