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

// Lo que sobra en la respuesta, sin repetir lo ya explicado: una cuenta puesta en el lado contrario ya sale como «⇄»
export function extraLines(result) {
  const flipped = (result?.lines ?? []).filter((l) => l.status === 'side')
  return (result?.extra ?? []).filter((x) => !flipped.some((l) => x.side !== l.side && String(x.account).startsWith(l.account)))
}

// Las 4 situaciones de una línea esperada tras corregir (las calcula erp.grade_exercise)
export const LINE_STATUS = { ok: '✓', amount: '≈', side: '⇄', missing: '✕' }
