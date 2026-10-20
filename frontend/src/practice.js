// PRACTICAR (v0.40.0): supuestos prácticos autocorregidos. La base de datos (0054) guarda los enunciados y corrige
// (erp.grade_exercise / erp.submit_exercise); aquí solo se prepara la respuesta y se ordena lo que se enseña.

export const LEVELS = ['basic', 'medium', 'advanced']

// Una línea vacía del formulario de respuesta
export const emptyLine = () => ({ account_no: '', debit: '', credit: '' })

// Importe escrito a mano: «1.210,50», «1210,5», «1210.5» o «1 210» → número (0 si no se entiende)
export function parseAmount(text) {
  let s = String(text ?? '').trim().replace(/[\s€]/g, '')
  if (!s) return 0
  if (s.includes(',')) s = s.replace(/\./g, '').replace(',', '.')        // formato español: el punto separa miles
  else if (/^\d{1,3}(\.\d{3})+$/.test(s)) s = s.replace(/\./g, '')       // «1.210» sin decimales: miles
  const n = Number(s)
  return Number.isFinite(n) ? Math.round(n * 100) / 100 : 0
}

// Las líneas que se mandan a corregir: con cuenta y con importe (en un solo lado)
export function answerLines(lines) {
  return lines
    .map((l) => ({ account_no: String(l.account_no ?? '').replace(/\D/g, ''), debit: parseAmount(l.debit), credit: parseAmount(l.credit) }))
    .filter((l) => l.account_no && (l.debit || l.credit))
}

// Totales del Debe y del Haber de la respuesta (en céntimos para no arrastrar decimales)
export function answerTotals(lines) {
  const c = (v) => Math.round(parseAmount(v) * 100)
  const debit = lines.reduce((s, l) => s + c(l.debit), 0)
  const credit = lines.reduce((s, l) => s + c(l.credit), 0)
  return { debit: debit / 100, credit: credit / 100, balanced: debit === credit && debit > 0 }
}

// Supuestos agrupados por nivel, cada uno con su progreso (de erp.v_exercise_progress)
export function groupByLevel(exercises, progress = []) {
  const p = Object.fromEntries(progress.map((r) => [r.key, r]))
  return LEVELS.map((level) => ({
    level,
    items: exercises.filter((x) => x.level === level).sort((a, b) => a.sort - b.sort)
      .map((x) => ({ ...x, progress: p[x.key] ?? { attempts: 0, best_score: 0, solved: false } })),
  })).filter((g) => g.items.length > 0)
}

// Resumen del progreso: resueltos, intentados y total
export function progressSummary(progress = []) {
  return {
    total: progress.length,
    solved: progress.filter((r) => r.solved).length,
    attempted: progress.filter((r) => Number(r.attempts) > 0).length,
  }
}

// Estado de un supuesto en la lista
export function exerciseState(progress) {
  if (progress?.solved) return 'solved'
  if (Number(progress?.attempts) > 0) return 'tried'
  return 'new'
}

// El siguiente supuesto (en el orden de la lista); después del último, el primero sin resolver
export function nextExercise(exercises, key, progress = []) {
  const list = [...exercises].sort((a, b) => a.sort - b.sort)
  const i = list.findIndex((x) => x.key === key)
  const solved = new Set(progress.filter((r) => r.solved).map((r) => r.key))
  const after = list.slice(i + 1).find((x) => !solved.has(x.key)) ?? list.find((x) => x.key !== key && !solved.has(x.key))
  return after ?? list[i + 1] ?? null
}

// Lo que sobra en la respuesta, sin repetir lo ya explicado: una cuenta puesta en el lado contrario ya sale como «⇄».
// v0.40.1: las que no son cuentas del PGC traen su motivo (reason: 'invalid' · 'not_in_pgc') y siempre se enseñan
export function extraLines(result) {
  const flipped = (result?.lines ?? []).filter((l) => l.status === 'side')
  return (result?.extra ?? []).filter((x) => x.reason || !flipped.some((l) => x.side !== l.side && String(x.account).startsWith(l.account)))
}

// Las 4 situaciones de una línea esperada tras corregir (las calcula erp.grade_exercise)
export const LINE_STATUS = { ok: '✓', amount: '≈', side: '⇄', missing: '✕' }

// EVALUAR LA IA (v0.40.0 · 0055) ----------------------------------------------------------------------------------
// ¿Se puede resolver este supuesto en esa empresa? El Tutor pone el impuesto de la empresa (IVA en la Península,
// IGIC en Canarias): un supuesto de IGIC en una empresa con IVA saldría mal por culpa del territorio, no de la IA.
export function fitsCompany(exercise, company) {
  if (!exercise.tax_type || !company) return true
  return (exercise.tax_type === 'IGIC') === (company.tax_territory === 'canary_islands')
}

// Las líneas del asiento que propuso el Tutor (validation.lines), como respuesta de un supuesto
export const tutorAnswer = (validation) => (validation?.lines ?? [])
  .map((l) => ({ account_no: String(l.account_no ?? ''), debit: Number(l.debit) || 0, credit: Number(l.credit) || 0 }))

// Errores del Tutor que paran la evaluación (no tiene sentido seguir: no quedan consultas o no hay permiso)
export const STOP_ERRORS = ['ai_user_limit', 'ai_quota', 'context_denied', 'not_signed_in', 'ai_not_configured', 'supabase_not_configured', 'db_not_updated']

// Resumen: supuestos evaluados, los que resolvió la IA y, de esos mismos, los que resolviste tú; modelos usados
export function aiSummary(progress = []) {
  const done = progress.filter((r) => r.ai_score != null)
  return {
    evaluated: done.length,
    aiSolved: done.filter((r) => r.ai_ok).length,
    userSolved: done.filter((r) => r.solved).length,
    aiAvg: done.length ? Math.round(done.reduce((s, r) => s + Number(r.ai_score), 0) / done.length) : 0,
    models: [...new Set(done.map((r) => r.ai_model).filter(Boolean))],
  }
}

// Cola de la evaluación: los de esta empresa, primero los que la IA aún no ha hecho (así, con poca cuota diaria,
// se completa en varios días) y, si hay límite, solo los que alcanzan
export function aiQueue(exercises, progress = [], company, remaining = null) {
  const done = new Set(progress.filter((r) => r.ai_score != null).map((r) => r.key))
  const fit = exercises.filter((x) => fitsCompany(x, company)).sort((a, b) => a.sort - b.sort)
  const queue = [...fit.filter((x) => !done.has(x.key)), ...fit.filter((x) => done.has(x.key))]
  return { fit: fit.length, queue: remaining == null ? queue : queue.slice(0, remaining) }
}
