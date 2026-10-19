import { describe, expect, it } from 'vitest'
import fs from 'node:fs'
import { fileURLToPath } from 'node:url'
import { answerLines, answerTotals, exerciseState, extraLines, groupByLevel, nextExercise, parseAmount, progressSummary } from '../src/practice'
import { SOURCES } from '../src/sources'
import { GLOSSARY } from '../src/glossary'
import es from '../src/i18n/es.js'

describe('practicar · la respuesta que se manda a corregir', () => {
  it('importes escritos a mano, en formato español o con punto decimal', () => {
    expect(parseAmount('1.210,50')).toBe(1210.5)
    expect(parseAmount('1210,5')).toBe(1210.5)
    expect(parseAmount('1210.5')).toBe(1210.5)
    expect(parseAmount('1.210')).toBe(1210)
    expect(parseAmount('2 420 €')).toBe(2420)
    expect(parseAmount('')).toBe(0)
    expect(parseAmount('abc')).toBe(0)
  })
  it('solo las líneas con cuenta e importe; la cuenta, solo con sus dígitos', () => {
    const lines = [{ account_no: '600', debit: '2.000', credit: '' }, { account_no: '472 ', debit: '420', credit: '' },
      { account_no: '400', debit: '', credit: '2.420' }, { account_no: '', debit: '5', credit: '' }, { account_no: '629', debit: '', credit: '' }]
    expect(answerLines(lines)).toEqual([
      { account_no: '600', debit: 2000, credit: 0 }, { account_no: '472', debit: 420, credit: 0 }, { account_no: '400', debit: 0, credit: 2420 }])
  })
  it('cuadre del Debe y el Haber (sin errores de redondeo)', () => {
    expect(answerTotals([{ debit: '0,1' }, { debit: '0,2' }, { credit: '0,3' }])).toEqual({ debit: 0.3, credit: 0.3, balanced: true })
    expect(answerTotals([{ debit: '100' }, { credit: '90' }]).balanced).toBe(false)
    expect(answerTotals([{ debit: '' }, { credit: '' }]).balanced).toBe(false)
  })
})

describe('practicar · corrección (la de erp.grade_exercise para la compra con IVA)', () => {
  // 600 bien, 472 al Haber (lado contrario), 400 por 2.000 (importe) y una 629 que sobra
  const r = { lines: [{ account: '600', side: 'debit', status: 'ok' }, { account: '472', side: 'debit', status: 'side' },
    { account: '400', side: 'credit', status: 'amount' }],
  extra: [{ account: '472', side: 'credit', amount: 420 }, { account: '629', side: 'debit', amount: 420 }] }
  it('lo que sobra no repite la cuenta puesta en el lado contrario', () => {
    expect(extraLines(r)).toEqual([{ account: '629', side: 'debit', amount: 420 }])
    expect(extraLines({ lines: [], extra: [] })).toEqual([])
    expect(extraLines(null)).toEqual([])
  })
})

describe('practicar · lista y progreso', () => {
  const exercises = [{ key: 'b', sort: 20, level: 'basic' }, { key: 'a', sort: 10, level: 'basic' }, { key: 'c', sort: 30, level: 'advanced' }]
  const progress = [{ key: 'a', attempts: 2, best_score: 100, solved: true }, { key: 'b', attempts: 1, best_score: 50, solved: false },
    { key: 'c', attempts: 0, best_score: 0, solved: false }]
  it('por nivel y en orden; sin intermedios no sale ese nivel', () => {
    expect(groupByLevel(exercises, progress).map((g) => `${g.level}:${g.items.map((x) => x.key).join(',')}`)).toEqual(['basic:a,b', 'advanced:c'])
  })
  it('resumen y estado de cada supuesto', () => {
    expect(progressSummary(progress)).toEqual({ total: 3, solved: 1, attempted: 2 })
    expect(progress.map(exerciseState)).toEqual(['solved', 'tried', 'new'])
    expect(exerciseState(undefined)).toBe('new')
  })
  it('el siguiente es el próximo sin resolver; tras el último, vuelve al primero sin resolver', () => {
    expect(nextExercise(exercises, 'a', progress).key).toBe('b')
    expect(nextExercise(exercises, 'c', progress).key).toBe('b')
    expect(nextExercise(exercises, 'b', progress).key).toBe('c')
  })
})

// Los supuestos de la base de datos (0054): sus fuentes y conceptos existen en la web, y sus pantallas en el menú
describe('practicar · datos de la migración 0054', () => {
  const dir = fileURLToPath(new URL('../../database/migrations', import.meta.url))
  const file = fs.existsSync(dir) && fs.readdirSync(dir).find((f) => f.startsWith('0054_'))
  const sql = file ? fs.readFileSync(`${dir}/${file}`, 'utf8') : ''
  it.skipIf(!file)('cada fuente citada (los {…} con claves de fuentes) está en src/sources.js', () => {
    const exercisesSql = sql.slice(sql.indexOf('insert into erp.exercises'), sql.indexOf('create table if not exists erp.exercise_attempts'))
    const ops = sql.slice(sql.indexOf('insert into erp.operations'), sql.indexOf('create table if not exists erp.exercises'))
    for (const part of [exercisesSql, ops]) {
      // el penúltimo/último array de texto de cada fila: '{pgc,liva}'
      const arrays = [...part.matchAll(/'\{([a-z0-9_,]+)\}'/g)].map((m) => m[1].split(','))
      const cited = arrays.flat().filter((k) => /[a-z]/.test(k))
      expect(cited.length).toBeGreaterThan(0)
      for (const k of cited) expect(SOURCES[k], k).toBeDefined()
    }
  })
  it.skipIf(!file)('cada pantalla de una operación existe en el menú y cada concepto en el glosario', () => {
    const ops = sql.slice(sql.indexOf('insert into erp.operations'), sql.indexOf('on conflict', sql.indexOf('insert into erp.operations')))
    const rows = [...ops.matchAll(/^\('([a-z_]+)', \d+, '(?:[^']|'')*', '(?:[^']|'')*', '([a-z]+)',/gm)]
    expect(rows.length).toBe(17)
    for (const [, key, screen] of rows) expect(es.nav[screen], `${key} → ${screen}`).toBeDefined()
    const concepts = [...sql.matchAll(/'\{[0-9,]+\}', '([A-Za-z]+)', '\{/g)].map((m) => m[1])
    expect(concepts.length).toBe(17)
    const exercisesSql = sql.slice(sql.indexOf('insert into erp.exercises'))
    const exConcepts = [...exercisesSql.matchAll(/, '([A-Za-z]+)'\)[,\r\n]/g)].map((m) => m[1])
    expect(exConcepts.length).toBe(14)
    for (const c of [...concepts, ...exConcepts]) expect(GLOSSARY[c], c).toBeDefined()
  })
})
