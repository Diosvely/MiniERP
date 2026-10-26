import { supabase } from './supabase'
import { buildPgc } from './pgc'

// PGC DE ESTUDIO (v0.48.0): cargar las 6 tablas de la migración 0071.
// Los datos son pequeños (unos 250 KB) y no cambian: se cargan una sola vez por sesión y se guardan en memoria
let cache = null
export function loadPgc() {
  if (cache) return cache
  cache = Promise.all([
    supabase.from('pgc_groups').select('*').order('grp'),
    supabase.from('pgc_subgroups').select('*').order('subgroup'),
    supabase.from('pgc_accounts').select('*').order('account'),
    supabase.from('pgc_cards').select('*'),
    supabase.from('pgc_valuation_rules').select('*').order('number'),
    supabase.from('pgc_principles').select('*').order('sort'),
  ]).then(([g, s, a, c, n, p]) => {
    const bad = [g, s, a, c, n, p].find((r) => r.error)?.error
    if (bad) { cache = null; throw bad }
    return buildPgc({ groups: g.data, subgroups: s.data, accounts: a.data, cards: c.data, rules: n.data, principles: p.data })
  })
  return cache
}
export function resetPgcCache() { cache = null }   // para las pruebas
