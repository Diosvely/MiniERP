import { describe, it, expect } from 'vitest'
import { deleteCompany } from '../src/deleteCompany.js'

// Cliente falso: cada llamada a delete_company_step borra hasta 5.000 asientos y devuelve los que quedan
const fakeClient = (entries, { failAt } = {}) => {
  let left = entries
  const calls = []
  return {
    calls,
    rpc: async (name, args) => {
      calls.push([name, args])
      if (failAt === calls.length) return { data: null, error: { message: 'Only the company admin can delete it' } }
      left = Math.max(left - 5000, 0)
      return { data: left, error: null }
    },
  }
}

describe('deleteCompany · borrar la empresa por tandas', () => {
  it('12.000 asientos → 3 tandas, avisa de lo que queda y termina en 0', async () => {
    const c = fakeClient(12000)
    const seen = []
    await deleteCompany(c, 'e1', (n) => seen.push(n))
    expect(seen).toEqual([7000, 2000, 0])
    expect(c.calls).toHaveLength(3)
    expect(c.calls[0]).toEqual(['delete_company_step', { p_company: 'e1' }])
  })
  it('empresa sin asientos → una sola llamada (borra la empresa)', async () => {
    const c = fakeClient(0)
    await deleteCompany(c, 'e1')
    expect(c.calls).toHaveLength(1)
  })
  it('si la base de datos lo rechaza, para y lanza el error', async () => {
    const c = fakeClient(12000, { failAt: 2 })
    await expect(deleteCompany(c, 'e1')).rejects.toMatchObject({ message: /Only the company admin/ })
    expect(c.calls).toHaveLength(2)
  })
})
