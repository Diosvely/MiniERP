// v0.59.0 · Empresas sintéticas con semilla (erp.create_synthetic_company, migración 0086)
// Con un número (la semilla), un perfil y los meses, cualquiera obtiene la misma contabilidad ficticia: sirve para
// aprender y para informar de un error sin compartir datos reales.
import { version } from '../package.json'

export const APP_VERSION = version
export const SEED_MIN = 1
export const SEED_MAX = 999999
export const PROFILES = ['services', 'trade', 'workshop', 'incidents']
// Meses mínimos de cada perfil (como erp.synthetic_profiles): «incidencias» necesita el 2T y un vencido de 90 días
export const MIN_MONTHS = { services: 1, trade: 1, workshop: 1, incidents: 6 }

// Una semilla válida: un número entero de 1 a 999.999 (lo que escriba la persona, sin espacios ni puntos)
export function parseSeed(text) {
  const s = String(text ?? '').replace(/[\s.]/g, '')
  if (!/^\d+$/.test(s)) return null
  const n = Number(s)
  return n >= SEED_MIN && n <= SEED_MAX ? n : null
}

// Una semilla propuesta al azar (solo para no tener que inventarla: lo que cuenta es la que se usa)
export const randomSeed = (rnd = Math.random) => SEED_MIN + Math.floor(rnd() * (SEED_MAX - SEED_MIN + 1))

// Los meses que se pueden elegir con un perfil
export const monthsFor = (profile) => Array.from({ length: 12 - (MIN_MONTHS[profile] ?? 1) + 1 }, (_, i) => (MIN_MONTHS[profile] ?? 1) + i)

// El nombre del último mes (para «De enero a junio»), en el idioma de la persona
export const monthName = (n, language = 'es') => new Date(2026, n - 1, 1).toLocaleString(language === 'en' ? 'en-GB' : 'es-ES', { month: 'long' })

// Si los meses elegidos no valen para el perfil nuevo, el mínimo del perfil
export const fitMonths = (profile, months) => Math.max(MIN_MONTHS[profile] ?? 1, Math.min(12, months))

// ¿Dónde se crea? Como al importar: importCard (temporary.js) decide si es temporal, permanente o si no cabe.

// El texto de «Copiar datos para informar de un error»: lo que hace falta para reproducirlo, nada personal
// (ni el email, ni el nombre de la empresa, ni sus identificadores internos)
export function reportText({ company, fingerprint, route, language = 'es', t }) {
  const screen = String(route ?? '').replace(/^#?\/?empresa\/[^/]+\/?/, '') || 'home'
  return [
    `Mini ERP v${APP_VERSION}`,
    `${t('syn.report.seed')}: ${company.synthetic_seed}`,
    `${t('syn.report.profile')}: ${company.synthetic_profile} (${t(`syn.profile.${company.synthetic_profile}`)})`,
    `${t('syn.report.months')}: ${company.synthetic_months}`,
    `${t('syn.report.fingerprint')}: ${fingerprint ?? '—'}`,
    `${t('syn.report.screen')}: ${screen}`,
    `${t('syn.report.workDate')}: ${company.work_date ?? '—'}`,
    `${t('syn.report.language')}: ${language}`,
  ].join('\n')
}

// v0.59.1 · Generar por tandas. Supabase corta cada llamada de la web a los ~8 s, así que la base de datos prepara la
// empresa y su plan (create_synthetic_company) y la web pide las operaciones en tandas (synthetic_step). Si una tanda
// se corta por tiempo, se repite con la mitad (hasta BATCH_MIN). step(companyId, n) → { data, error } de la tanda.
export const BATCH = 25
export const BATCH_MIN = 5
export const isTimeout = (error) => /statement timeout|canceling statement|57014/i.test(`${error?.message ?? ''} ${error?.code ?? ''}`)

export async function runSteps(step, companyId, { batch = BATCH, onProgress = () => {}, maxCalls = 2000 } = {}) {
  let n = batch
  for (let calls = 0; calls < maxCalls; calls++) {
    const { data, error } = await step(companyId, n)
    if (error) {
      if (isTimeout(error) && n > BATCH_MIN) { n = Math.max(BATCH_MIN, Math.floor(n / 2)); continue }
      return { error }
    }
    onProgress(data)
    if (data.left === 0) return { data }
  }
  return { error: { message: 'The generation did not finish' } }
}

// El porcentaje hecho (0-100) de una respuesta de synthetic_step / synthetic_progress
export const progressPct = (p) => (p?.total ? Math.floor((100 * p.done) / p.total) : 0)
