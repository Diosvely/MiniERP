import { describe, expect, it } from 'vitest'
import { balanced, breakdown, entriesPreview, expense, sign } from '../src/corporateTax'
import { friendlyError } from '../src/errors'
import es from '../src/i18n/es.js'
import en from '../src/i18n/en.js'
import fs from 'node:fs'
import { fileURLToPath } from 'node:url'

// Las cifras son las de los supuestos de referencia de la base de datos (fases 52 y 53), calculadas a mano
const s1 = { pre_tax_result: 182000, permanent: 1000, temporary_increase: 2600, temporary_decrease: 0, base_before_losses: 185600,
  losses_compensated: 0, taxable_base: 185600, quota: 37976, withholdings: 10000, differential: 27976, current_tax: 37976,
  deferred_tax: -546, tax_expense: 37430, net_result: 144570, deferred_rate: 21, loss_credit: 0, loss_credit_used: 0 }

describe('Impuesto sobre Sociedades · cómo se enseña el cálculo', () => {
  it('del resultado contable a la cuota diferencial, en el orden de la declaración', () => {
    expect(breakdown(s1).map((r) => `${r.key}:${r.amount}`)).toEqual(['preTax:182000', 'permanent:1000', 'tempIncrease:2600', 'tempDecrease:0',
      'baseBefore:185600', 'losses:0', 'taxableBase:185600', 'quota:37976', 'withholdings:-10000', 'differential:27976'])
    expect(expense(s1).map((r) => r.amount)).toEqual([37976, -546, 37430, 144570])
    expect(breakdown(null)).toEqual([])
  })
  it('signo de los ajustes', () => {
    expect([sign({ direction: 'increase' }), sign({ direction: 'decrease' })]).toEqual([1, -1])
  })
  it('supuesto 1: los dos asientos, como los hace la base de datos', () => {
    const e = entriesPreview(s1)
    expect(e.current).toEqual([{ account: '6300', debit: 37976, credit: 0 }, { account: '473', debit: 0, credit: 10000 }, { account: '4752', debit: 0, credit: 27976 }])
    expect(e.deferred).toEqual([{ account: '4740', debit: 546, credit: 0 }, { account: '6301', debit: 0, credit: 546 }])
    expect(balanced(e.current) && balanced(e.deferred)).toBe(true)
  })
  it('supuesto 3: pagos a cuenta mayores que la cuota → 4709', () => {
    const e = entriesPreview({ ...s1, current_tax: 5000, withholdings: 8000, differential: -3000, temporary_increase: 0, deferred_tax: 0 })
    expect(e.current).toEqual([{ account: '6300', debit: 5000, credit: 0 }, { account: '473', debit: 0, credit: 8000 }, { account: '4709', debit: 3000, credit: 0 }])
    expect(e.deferred).toEqual([])
  })
  it('supuesto 2: crédito por pérdidas (2026) y su aplicación (2027)', () => {
    const y26 = entriesPreview({ ...s1, current_tax: 0, withholdings: 0, differential: 0, temporary_increase: 0, deferred_rate: 25, loss_credit: 12500, deferred_tax: -12500 })
    expect(y26.current).toEqual([])
    expect(y26.deferred).toEqual([{ account: '4745', debit: 12500, credit: 0 }, { account: '6301', debit: 0, credit: 12500 }])
    const y27 = entriesPreview({ ...s1, current_tax: 7500, withholdings: 0, differential: 7500, temporary_increase: 0, deferred_rate: 25, loss_credit_used: 12500, deferred_tax: 12500 })
    expect(y27.deferred).toEqual([{ account: '4745', debit: 0, credit: 12500 }, { account: '6301', debit: 12500, credit: 0 }])
    expect(balanced(y27.current) && balanced(y27.deferred)).toBe(true)
  })
  it('supuesto 4: una reversión mayor que el aumento (2027) va al Haber de la 4740', () => {
    const e = entriesPreview({ ...s1, temporary_increase: 250, temporary_decrease: 605, deferred_rate: 25, deferred_tax: 88.75 })
    expect(e.deferred).toEqual([{ account: '4740', debit: 0, credit: 88.75 }, { account: '6301', debit: 88.75, credit: 0 }])
  })
  it('las cuentas de los asientos tienen su nombre', () => {
    for (const a of ['6300', '6301', '473', '4752', '4709', '4740', '4745']) expect(es.ct.account[a], a).toBeTruthy()
  })
  it('los errores del impuesto se explican', () => {
    const t = (k) => k.split('.').reduce((o, p) => o?.[p], es) ?? k
    expect(friendlyError('A later corporate tax is posted: undo it first (it uses this one)', t, 'es').to).toBe('corporate_tax')
    expect(friendlyError('This entry belongs to the corporate income tax: undo it from Corporate tax', t, 'es').title).toMatch(/Impuesto sobre Sociedades/)
    expect(friendlyError('The year 2026 is already closed (regularization posted): the corporate tax goes before it', t, 'es').title).toMatch(/2026/)
    expect(friendlyError('No corporate tax rates for 2031 (micro): add them to erp.corporate_tax_rates', t, 'es').title).toMatch(/2031/)
  })
})

// v0.41.0 · Integración: cada módulo que controla cuentas (erp.control_rules) tiene su nombre en los avisos
// («La 630 la registra …»). Antes faltaba el de Nóminas y el aviso enseñaba la clave «ctl.module.payroll».
describe('cuentas controladas: nombre de cada módulo', () => {
  const dir = fileURLToPath(new URL('../../database/migrations', import.meta.url))
  const modules = new Set()
  if (fs.existsSync(dir)) {
    for (const f of fs.readdirSync(dir).filter((x) => x.endsWith('.sql'))) {
      for (const m of fs.readFileSync(`${dir}/${f}`, 'utf8').matchAll(/'\{([a-z_,]+)\}', '(?:both|debit|credit)'/g)) {
        m[1].split(',').forEach((x) => modules.add(x))
      }
    }
  }
  it.skipIf(!modules.size)('es y en tienen todos (también corporate_tax y payroll)', () => {
    expect(modules.has('corporate_tax')).toBe(true)
    for (const m of modules) {
      expect(es.ctl.module[m], `es: ${m}`).toBeTruthy()
      expect(en.ctl.module[m], `en: ${m}`).toBeTruthy()
    }
  })
  it('el paso del asistente y los avisos del cierre tienen texto', () => {
    for (const d of [es, en]) {
      expect(d.wiz.step.corporate_tax.pending).toBeTruthy()
      expect(d.check.corporate_tax_missing).toContain('{d}')
      expect(d.check.withholdings_left).toContain('{d}')
    }
  })
})

// v0.42.0 · Gastos de constitución en la 113: el ahorro de impuesto va a reservas (las mismas cifras que la fase 56)
describe('Impuesto sobre Sociedades · gastos cargados a reservas', () => {
  const c = { current_tax: 25000, equity_tax_effect: 300, withholdings: 0, differential: 24700, deferred_tax: 0, deferred_rate: 25,
    temporary_increase: 0, temporary_decrease: 0, loss_credit: 0, loss_credit_used: 0 }
  it('6300 25.000 / 113 300 · 4752 24.700, y cuadra', () => {
    const { current } = entriesPreview(c)
    expect(current).toEqual([{ account: '6300', debit: 25000, credit: 0 }, { account: '113', debit: 0, credit: 300 }, { account: '4752', debit: 0, credit: 24700 }])
    expect(balanced(current)).toBe(true)
  })
})
