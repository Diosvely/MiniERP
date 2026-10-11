import { describe, it, expect, vi, afterEach } from 'vitest'
import { parseAnalysis, onRequestPost as analyst, isUuid, readBody } from '../functions/api/ai.js'
import { parseProposal, responseText, onRequestPost as tutor } from '../functions/api/tutor.js'

const env = { AI: { run: vi.fn() }, VITE_SUPABASE_URL: 'https://x.supabase.co', VITE_SUPABASE_KEY: 'pub' }
const UUID = '11111111-2222-4333-8444-555555555555'
const post = (body) => new Request('https://x/api', { method: 'POST', headers: { Authorization: 'Bearer t' }, body: typeof body === 'string' ? body : JSON.stringify(body) })
afterEach(() => vi.restoreAllMocks())

describe('parseAnalysis · respuesta del Analista IA', () => {
  const good = { summary: 'Bien', strengths: ['a'], alerts: [], auditor_questions: ['q'], learning: 'l' }
  it('JSON limpio', () => expect(parseAnalysis(JSON.stringify(good))).toEqual(good))
  it('JSON envuelto en ```json y con texto alrededor', () => {
    expect(parseAnalysis('Aquí tienes:\n```json\n' + JSON.stringify(good) + '\n```')).toEqual(good)
  })
  it('recorta las listas a 4 y descarta lo que no es texto', () => {
    const a = parseAnalysis(JSON.stringify({ ...good, strengths: ['1', '2', 3, '', '4', '5', '6'] }))
    expect(a.strengths).toEqual(['1', '2', '4', '5'])
  })
  it('sin JSON o sin resumen → null', () => {
    expect(parseAnalysis('Lo siento, no sé.')).toBeNull()
    expect(parseAnalysis('{"alerts": []}')).toBeNull()
    expect(parseAnalysis('')).toBeNull()
  })
})

describe('parseProposal y responseText · Tutor de asientos', () => {
  it('limpia cuentas, lados e importes de la propuesta', () => {
    const p = parseProposal('```json\n{"explanation":"x","valuation_rule":"nrv-14","lines":[{"account":"572.1","side":"credit","amount":"100"},{"account":"600","side":"debit","amount":100}]}\n```')
    expect(p.valuation_rule).toBe('NRV14')
    expect(p.lines[0]).toMatchObject({ account: '5721', side: 'credit', amount: 100, role: 'other' })
  })
  it('sin lista de líneas → null', () => expect(parseProposal('{"explanation":"x"}')).toBeNull())
  it('lee los tres formatos de respuesta de los modelos', () => {
    expect(responseText({ response: 'a' })).toBe('a')
    expect(responseText({ choices: [{ message: { content: 'b' } }] })).toBe('b')
    expect(responseText({ output: [{ type: 'reasoning' }, { type: 'message', content: [{ text: 'c' }] }] })).toBe('c')
  })
})

describe('defensa de /api/ai y /api/tutor (v0.28.0)', () => {
  it('isUuid', () => {
    expect(isUuid(UUID)).toBe(true)
    expect(isUuid("x' or 1=1")).toBe(false)
    expect(isUuid(undefined)).toBe(false)
  })
  it('readBody: grande → too_large · roto → bad_request', async () => {
    expect(await readBody(post({ a: 'x'.repeat(3000) }), 2048)).toEqual({ error: 'too_large' })
    expect(await readBody(post('{roto'), 2048)).toEqual({ error: 'bad_request' })
    expect(await readBody(post({ a: 1 }), 2048)).toEqual({ body: { a: 1 } })
  })
  it('company_id que no es UUID → 400 sin llamar a Supabase', async () => {
    const spy = vi.spyOn(globalThis, 'fetch')
    expect((await analyst({ request: post({ company_id: 'c1', year: 2025 }), env })).status).toBe(400)
    expect((await tutor({ request: post({ company_id: '../x', text: 'Pago el alquiler' }), env })).status).toBe(400)
    expect(spy).not.toHaveBeenCalled()
  })
  it('permiso denegado → 403 solo con el código, sin el texto de PostgreSQL', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(JSON.stringify({ message: 'permission denied for table journal_entries' }), { status: 403 }))
    vi.spyOn(console, 'error').mockImplementation(() => {})
    const r = await analyst({ request: post({ company_id: UUID, year: 2025 }), env })
    expect(r.status).toBe(403)
    expect(await r.json()).toEqual({ error: 'context_denied' })
    expect(console.error).toHaveBeenCalled()                 // el detalle va al registro de Cloudflare
  })
  it('sin sesión → 401', async () => {
    const r = await analyst({ request: new Request('https://x/api', { method: 'POST', body: '{}' }), env })
    expect(r.status).toBe(401)
  })
})
