// FECHA DE TRABAJO de cada empresa (la "Work Date" de Business Central)
// Es la fecha que proponen todos los filtros y formularios: el año de los informes, el "Desde" del diario,
// el trimestre de las liquidaciones y la fecha de los asientos y facturas nuevos.
//   · Empresa al día (tiene un ejercicio ABIERTO que incluye hoy) → hoy.
//   · Empresa importada o histórica → la fecha de su ÚLTIMO asiento contabilizado
//     (una empresa de 2019-2024 se abre en diciembre de 2024, no en un 2026 vacío).
//   · Empresa sin ejercicios ni asientos → hoy.
// Se calcula al abrir la empresa (CompanyView) y viaja dentro de company.work_date.

// Hoy en la hora LOCAL (toISOString() da la fecha en UTC: cerca de medianoche saldría el día anterior o el siguiente)
export function todayIso(now = new Date()) {
  const p = (n) => String(n).padStart(2, '0')
  return `${now.getFullYear()}-${p(now.getMonth() + 1)}-${p(now.getDate())}`
}

//   years:      [{ starting_date, ending_date, status }] de la empresa
//   lastPosted: fecha del último asiento contabilizado (o null)
export function computeWorkDate({ today = todayIso(), years = [], lastPosted = null } = {}) {
  const current = years.some((y) => y.status === 'open' && y.starting_date <= today && today <= y.ending_date)
  if (current) return today
  return lastPosted ?? today
}

export const workDate = (company) => company?.work_date ?? todayIso()
export const workYear = (company) => Number(workDate(company).slice(0, 4))
export const workQuarter = (company) => Math.floor((Number(workDate(company).slice(5, 7)) - 1) / 3) + 1
export const workMonthStart = (company) => `${workDate(company).slice(0, 8)}01`
