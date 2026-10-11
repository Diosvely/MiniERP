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
})
