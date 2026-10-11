// BORRAR UNA EMPRESA ENTERA, POR TANDAS
// La base de datos (erp.delete_company_step, migración 0029) borra 5.000 asientos por llamada y devuelve los que quedan.
// Aquí se repite hasta llegar a 0: así ninguna llamada pasa del límite de tiempo de Supabase (unos 8 s),
// aunque la empresa tenga años de datos importados. Igual que la importación, que va mes a mes.
//   client:     el cliente de Supabase (se recibe como parámetro para poder probarlo sin conexión)
//   onProgress: se llama tras cada tanda con los asientos que quedan
export const MAX_STEPS = 1000   // 5 millones de asientos: si se llega aquí, algo va mal

export async function deleteCompany(client, companyId, onProgress = () => {}) {
  for (let step = 0; step < MAX_STEPS; step++) {
    const { data: left, error } = await client.rpc('delete_company_step', { p_company: companyId })
    if (error) throw error
    onProgress(left)
    if (left === 0) return
  }
  throw new Error('The company could not be deleted: too many steps')
}
