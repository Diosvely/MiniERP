import { describe, it, expect } from 'vitest'
import { legalFormFromTaxId, canWithhold, allowedWithholdings } from '../src/partnerTax.js'
import { needsRepair } from '../functions/api/tutor.js'

const CODES = [
  { code: 'IRPF15', kind: 'professional' }, { code: 'IRPF7', kind: 'professional' }, { code: 'IRPF19', kind: 'rent' },
]

describe('datos fiscales del tercero (v0.31.0)', () => {
  it('la forma jurídica sale del NIF, como en la base de datos', () => {
    expect(legalFormFromTaxId('12345678Z')).toBe('individual')
    expect(legalFormFromTaxId('x-1234567-l')).toBe('individual')
    expect(legalFormFromTaxId('B12345674')).toBe('company')
    expect(legalFormFromTaxId('FR123456789')).toBeNull()
    expect(legalFormFromTaxId('')).toBeNull()
  })
  it('solo se retiene a proveedores y acreedores', () => {
    expect(canWithhold('creditor') && canWithhold('vendor')).toBe(true)
    expect(canWithhold('customer') || canWithhold('debtor')).toBe(false)
    expect(allowedWithholdings(CODES, 'customer', 'individual')).toEqual([])
  })
  it('a una sociedad no se le ofrece la retención de profesionales, pero sí la de alquiler', () => {
    expect(allowedWithholdings(CODES, 'creditor', 'company').map((c) => c.code)).toEqual(['IRPF19'])
    expect(allowedWithholdings(CODES, 'creditor', 'individual')).toHaveLength(3)
    expect(allowedWithholdings(CODES, 'creditor', null)).toHaveLength(3)
  })
})

describe('tutor · qué avisos se le devuelven a la IA', () => {
  it('errores y avisos de retención (warning) sí; un recordatorio (info) no', () => {
    const checks = [
      { level: 'warning', code: 'withholding_missing', detail: '623 → IRPF15' },
      { level: 'info', code: 'withholding_missing', detail: '621 → IRPF19' },
      { level: 'warning', code: 'tax_amount_fixed' },
      { level: 'error', code: 'unbalanced' },
      { level: 'info', code: 'partner_amount_fixed' },
    ]
    expect(needsRepair(checks).map((c) => `${c.level}:${c.code}`)).toEqual(['warning:withholding_missing', 'error:unbalanced'])
  })
})
