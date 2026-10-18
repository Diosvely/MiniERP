import { describe, it, expect } from 'vitest'
import { friendlyError } from '../src/errors.js'
import { tEs, tEn } from './helpers.js'

describe('friendlyError · errores de la base de datos en lenguaje claro', () => {
  it('asiento descuadrado: importes en formato español y sin pantalla', () => {
    const f = friendlyError('Unbalanced entry: debit 1210.00 ≠ credit 1000.00 (difference 210.00)', tEs, 'es')
    expect(f.title).toBe('El asiento no cuadra: Debe 1.210,00 y Haber 1.000,00')
    expect(f.hint).toContain('210,00')
    expect(f.to).toBeNull()
    expect(f.technical).toMatch(/^Unbalanced entry/)
  })
  it('retenciones en la ficha del tercero (v0.31.0)', () => {
    const f = friendlyError('Professional withholding (IRPF) does not apply to companies', tEs, 'es')
    expect(f.title).toBe('A una entidad no se le practica la retención de profesionales')
    expect(f.to).toBe('partners')
    expect(friendlyError('Withholding only applies to vendors and creditors', tEn, 'en').title).toContain('vendors and creditors')
  })
  it('cobros y pagos (v0.32.0)', () => {
    const f = friendlyError('Invoice C-2026-0001 only has 560.00 pending (you applied 600.00)', tEs, 'es')
    expect(f.title).toBe('La factura C-2026-0001 solo tiene 560,00 pendientes (has aplicado 600,00)')
    expect(friendlyError('This entry belongs to a payment: cancel the payment instead', tEs, 'es').to).toBe('payments')
    expect(friendlyError('Choose a cash or bank account (57)', tEn, 'en').title).toBe('Choose a bank or cash account (57)')
  })
  it('cuenta controlada en modo estricto (v0.33.0): lleva a la pantalla de su módulo', () => {
    const msg = (a, m) => `Account ${a} is controlled by ${m}: register it from that screen (or switch the company to guided mode)`
    const f = friendlyError(msg('41000001', 'invoices, payments'), tEs, 'es')
    expect(f.title).toBe('La 41000001 es una cuenta controlada: no admite asientos manuales')
    expect(f.to).toBe('payments')
    expect(friendlyError(msg('47200021', 'invoices, settlement'), tEs, 'es').to).toBe('invoices')
    expect(friendlyError(msg('47500001', 'settlement'), tEn, 'en').to).toBe('settlement')
  })
  it('sin ejercicio: lleva a Cierre del ejercicio', () => {
    const f = friendlyError({ message: 'No fiscal year for date 2027-01-15' }, tEs, 'es')
    expect(f.title).toContain('2027-01-15')
    expect(f.to).toBe('closing')
  })
  it('traduce palabras sueltas del mensaje (credit → acreedor, VAT → IVA)', () => {
    expect(friendlyError('Account 57000001 (Caja) would have a credit balance of -50.00 on 2026-03-01: it is blocked for inverse balances', tEs, 'es').title)
      .toContain('saldo acreedor de -50,00')
    expect(friendlyError('VAT quarter 1T 2026 is already settled: post this with a later date', tEs, 'es').title).toBe('El 1T de 2026 (IVA) ya está liquidado')
  })
  it('errores de inicio de sesión, permisos, red y CAPTCHA', () => {
    expect(friendlyError('Invalid login credentials', tEs).title).toBe('Correo o contraseña incorrectos')
    expect(friendlyError('new row violates row-level security policy for table "x"', tEs).title).toMatch(/permiso/)
    expect(friendlyError('TypeError: Failed to fetch', tEs).title).toMatch(/conexión/)
    expect(friendlyError('captcha protection: request disallowed (captcha verification process failed)', tEs).title).toMatch(/robot/)
    expect(friendlyError('canceling statement due to statement timeout', tEs).title).toBe('La consulta ha tardado demasiado')
  })
  it('en inglés', () => {
    expect(friendlyError('Invoice A-7 of Abogada Ruiz is already registered', tEn, 'en').title).toBe('Invoice A-7 from Abogada Ruiz is already registered')
  })
  it('un mensaje desconocido o ya traducido se muestra tal cual', () => {
    expect(friendlyError('La contraseña debe tener al menos 8 caracteres.', tEs)).toEqual({ title: 'La contraseña debe tener al menos 8 caracteres.', hint: '', to: null, technical: null })
  })
  it('sin error no hay caja', () => {
    expect(friendlyError('', tEs)).toBeNull()
    expect(friendlyError(null, tEs)).toBeNull()
  })
  it('nóminas (v0.38.0): llevan a la pantalla Nóminas', () => {
    expect(friendlyError('This entry belongs to a payroll: undo it from Payroll', tEs, 'es').to).toBe('payroll')
    expect(friendlyError('The payroll of 01/2026 is already posted', tEs, 'es').title).toBe('La nómina de 01/2026 ya está contabilizada')
    expect(friendlyError('There are no contribution rates for 2027: they are published each year (Orden de cotización)', tEn, 'en').title)
      .toBe('There are no contribution rates for 2027')
    const msg = 'Account 46500001 is controlled by payroll: register it from that screen (or switch the company to guided mode)'
    expect(friendlyError(msg, tEs, 'es').to).toBe('payroll')
  })
})
