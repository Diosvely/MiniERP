// LEER TODAS LAS FILAS, POR PÁGINAS
// Supabase (PostgREST) devuelve como mucho 1.000 filas por consulta ("Max rows" del proyecto).
// El mayor de una cuenta con mucho movimiento (bancos, clientes…) puede tener miles de apuntes:
// sin paginar se verían solo los 1.000 primeros y los totales saldrían mal, sin ningún aviso.
//   build: función que crea la consulta (cada página necesita una nueva), p. ej.
//          () => supabase.rpc('general_ledger', {...})
// → { data, error } igual que una consulta normal, con TODAS las filas
export const PAGE = 1000

export async function fetchAll(build, page = PAGE) {
  const rows = []
  for (let from = 0; ; from += page) {
    const { data, error } = await build().range(from, from + page - 1)
    if (error) return { data: null, error }
    rows.push(...(data ?? []))
    if (!data || data.length < page) return { data: rows, error: null }
  }
}
