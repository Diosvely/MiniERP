import { describe, expect, it } from 'vitest'
import { FORM_SOURCES, SOURCES, isStale } from '../src/sources'
import { formResult, group349, groupBoxes, totals347 } from '../src/taxForms'

// Las cifras de los supuestos de referencia de la base de datos (fases 46 y 47)
describe('modelos (supuestos de las fases 46 y 47)', () => {
  const rows303 = [
    { section: 'devengado', box: '27', kind: 'amount', amount: 2982 }, { section: 'deducible', box: '45', kind: 'amount', amount: 2793 },
    { section: 'resultado', box: '46', kind: 'amount', amount: 189 }, { section: 'resultado', box: '71', kind: 'amount', amount: 189 },
    { section: 'informacion', box: '59', kind: 'base', amount: 3000 }]
  it('casillas agrupadas por apartado, en el orden del modelo', () => {
    expect(groupBoxes([...rows303].reverse()).map((g) => `${g.section}:${g.rows.map((r) => r.box).join(',')}`))
      .toEqual(['devengado:27', 'deducible:45', 'resultado:71,46', 'informacion:59'])
  })
  it('resultado de cada modelo: 303 → 71 a ingresar; 420 → 45 a compensar; 390 → 86', () => {
    expect(formResult('303', rows303)).toEqual({ box: '71', amount: 189, outcome: 'pay' })
    expect(formResult('420', [{ box: '45', amount: '-38.00' }])).toEqual({ box: '45', amount: -38, outcome: 'credit' })
    expect(formResult('390', [{ box: '86', amount: 0 }]).outcome).toBe('zero')
    expect(formResult('425', [])).toBeNull()
  })
  it('347: ventas, compras y terceros sin NIF', () => {
    expect(totals347([{ op_key: 'B', total: '3630.00' }, { op_key: 'B', total: 4840, missing_vat_no: true },
                      { op_key: 'A', total: 6050 }, { op_key: 'A', total: '4000' }]))
      .toEqual({ sales: 8470, purchases: 10050, count: 4, missing: 1 })
  })
  it('349: operaciones por clave y rectificaciones aparte', () => {
    const g = group349([{ section: 'operation', op_key: 'E', amount: 30000 }, { section: 'operation', op_key: 'S', amount: '25000' },
                        { section: 'operation', op_key: 'A', amount: 10000 }, { section: 'rectification', op_key: 'E', amount: 28000 }])
    expect(g.byKey).toEqual({ E: 30000, S: 25000, A: 10000 })
    expect(g.rectifications).toHaveLength(1)
  })
})

describe('base documental: fuentes oficiales', () => {
  it('cada fuente tiene emisor, enlace https, fecha de comprobación y textos en los dos idiomas', () => {
    for (const [k, s] of Object.entries(SOURCES)) {
      expect(s.url, k).toMatch(/^https:\/\//)
      expect(['AEAT', 'ATC', 'BOE'], k).toContain(s.issuer)
      expect(s.checked, k).toMatch(/^\d{4}-\d{2}-\d{2}$/)
      expect(s.es?.title && s.es?.ref && s.en?.title && s.en?.ref, k).toBeTruthy()
    }
  })
  it('cada modelo cita fuentes que existen', () => {
    for (const [form, ids] of Object.entries(FORM_SOURCES)) {
      expect(ids.length, form).toBeGreaterThan(0)
      for (const id of ids) expect(SOURCES[id], `${form}: ${id}`).toBeDefined()
    }
  })
  it('una fuente sin revisar en más de un año se avisa', () => {
    expect(isStale({ checked: '2026-10-18' }, '2027-10-18')).toBe(false)
    expect(isStale({ checked: '2026-10-18' }, '2027-10-19')).toBe(true)
  })
})
