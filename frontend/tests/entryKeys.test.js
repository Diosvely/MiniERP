import { describe, expect, it } from 'vitest'
import { cents, enterAction, lineKeyAction, removeLineFrom, suggestionFor } from '../src/entryKeys'

const L = (accountText, debit = '', credit = '', extra = {}) => ({ accountText, debit, credit, ...extra })

describe('asiento en una línea · importe propuesto (v0.41.1)', () => {
  it('propone en la línea vacía lo que falta, en el lado contrario', () => {
    const lines = [L('60000001', '1000'), L('47200021', '210'), L('')]
    expect(suggestionFor(lines, 2)).toEqual({ side: 'credit', cents: 121000 })
    expect(suggestionFor([L('57200001', '', '50,5'), L('')], 1)).toEqual({ side: 'debit', cents: 5050 })
  })
  it('no propone nada si ya cuadra o si la línea ya tiene importe', () => {
    expect(suggestionFor([L('600', '100'), L('400', '', '100'), L('')], 2)).toBe(null)
    expect(suggestionFor([L('600', '100'), L('400', '', '40')], 1)).toBe(null)
  })
  it('cuenta en céntimos: 0,1 + 0,2 = 0,3', () => {
    expect(suggestionFor([L('a', '0,1'), L('b', '0.2'), L('')], 2)).toEqual({ side: 'credit', cents: 30 })
    expect(cents('1210,50')).toBe(121050)
  })
})

describe('asiento en una línea · Enter', () => {
  const base = { i: 0, balanced: false, resolved: true, suggestion: null }
  it('en la cuenta: al Debe (aunque lo que falta vaya al Haber: la 472 de una compra también va al Debe); o al lado que pide la plantilla', () => {
    expect(enterAction({ ...base, field: 'account', line: L('600') })).toEqual({ type: 'focus', line: 0, field: 'debit' })
    expect(enterAction({ ...base, field: 'account', line: L('472'), suggestion: { side: 'credit', cents: 100 } })).toEqual({ type: 'focus', line: 0, field: 'debit' })
    expect(enterAction({ ...base, field: 'account', line: L('472', '', '', { expect: 'debit' }), suggestion: { side: 'credit', cents: 1 } })).toEqual({ type: 'focus', line: 0, field: 'debit' })
  })
  it('en la cuenta sin encontrar: se queda', () => {
    expect(enterAction({ ...base, field: 'account', line: L('999'), resolved: false })).toEqual({ type: 'stay' })
  })
  it('en una línea vacía: si el asiento cuadra, a «Contabilizar»; si no, se queda', () => {
    expect(enterAction({ ...base, field: 'account', line: L(''), balanced: true })).toEqual({ type: 'post' })
    expect(enterAction({ ...base, field: 'account', line: L('') })).toEqual({ type: 'stay' })
  })
  it('en el Debe: con importe, a la línea siguiente; vacío, al Haber', () => {
    expect(enterAction({ ...base, field: 'debit', line: L('600', '100') })).toEqual({ type: 'next' })
    expect(enterAction({ ...base, field: 'debit', line: L('400') })).toEqual({ type: 'focus', line: 0, field: 'credit' })
  })
  it('en el campo del importe propuesto, vacío: lo pone (y después sigue)', () => {
    expect(enterAction({ ...base, field: 'credit', line: L('400'), suggestion: { side: 'credit', cents: 121000 } })).toEqual({ type: 'fill', side: 'credit' })
    expect(enterAction({ ...base, field: 'debit', line: L('572'), suggestion: { side: 'debit', cents: 5 } })).toEqual({ type: 'fill', side: 'debit' })
  })
  it('en el Haber: siempre a la línea siguiente (o una nueva)', () => {
    expect(enterAction({ ...base, field: 'credit', line: L('400', '', '50') })).toEqual({ type: 'next' })
    expect(enterAction({ ...base, field: 'credit', line: L('400') })).toEqual({ type: 'next' })
  })
})

describe('asiento en una línea · otras teclas', () => {
  const k = (key, mods = {}) => ({ key, ctrlKey: false, metaKey: false, ...mods })
  it('Ctrl + Supr borra la línea (también ⌘ + Supr en el Mac); Supr sola no', () => {
    expect(lineKeyAction(k('Delete', { ctrlKey: true }), 'debit', null)).toEqual({ type: 'remove' })
    expect(lineKeyAction(k('Delete', { metaKey: true }), 'account', null)).toEqual({ type: 'remove' })
    expect(lineKeyAction(k('Delete'), 'account', null)).toBe(null)
  })
  it('«=» pone el importe propuesto en su lado, solo en los importes y si hay propuesta', () => {
    expect(lineKeyAction(k('='), 'debit', { side: 'credit', cents: 5 })).toEqual({ type: 'fill', side: 'credit', stay: true })
    expect(lineKeyAction(k('='), 'account', { side: 'credit', cents: 5 })).toBe(null)
    expect(lineKeyAction(k('='), 'credit', null)).toBe(null)
  })
  it('«+» añade una línea debajo', () => {
    expect(lineKeyAction(k('+'), 'account', null)).toEqual({ type: 'add' })
  })
  it('borrar: con más de dos líneas se quita; con dos, se vacía', () => {
    const e = () => L('')
    expect(removeLineFrom([L('a'), L('b'), L('c')], 1, e).map((l) => l.accountText)).toEqual(['a', 'c'])
    expect(removeLineFrom([L('a'), L('b')], 0, e).map((l) => l.accountText)).toEqual(['', 'b'])
  })
})
