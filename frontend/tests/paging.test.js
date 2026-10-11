import { describe, it, expect } from 'vitest'
import { fetchAll } from '../src/paging.js'

// Consulta falsa con la misma interfaz que la de Supabase: build().range(desde, hasta) → { data, error }
const fakeQuery = (total, { failAt } = {}) => {
  const calls = []
  const build = () => ({
    range: async (from, to) => {
      calls.push([from, to])
      if (failAt === from) return { data: null, error: { message: 'canceling statement due to statement timeout' } }
      const data = []
      for (let i = from; i <= to && i < total; i++) data.push({ n: i })
      return { data, error: null }
    },
  })
  return { build, calls }
}

describe('fetchAll · leer todas las filas por páginas de 1.000', () => {
  it('2.500 filas → 3 páginas y ninguna perdida', async () => {
    const q = fakeQuery(2500)
    const { data, error } = await fetchAll(q.build)
    expect(error).toBeNull()
    expect(data).toHaveLength(2500)
    expect(data.at(-1).n).toBe(2499)
    expect(q.calls).toEqual([[0, 999], [1000, 1999], [2000, 2999]])
  })
  it('exactamente 1.000 filas → pide una página más (vacía) para saber que no hay más', async () => {
    const q = fakeQuery(1000)
    const { data } = await fetchAll(q.build)
    expect(data).toHaveLength(1000)
    expect(q.calls).toHaveLength(2)
  })
  it('sin filas → lista vacía', async () => {
    expect((await fetchAll(fakeQuery(0).build)).data).toEqual([])
  })
  it('si una página falla, devuelve el error (no media lista)', async () => {
    const { data, error } = await fetchAll(fakeQuery(2500, { failAt: 1000 }).build)
    expect(data).toBeNull()
    expect(error.message).toMatch(/statement timeout/)
  })
})
