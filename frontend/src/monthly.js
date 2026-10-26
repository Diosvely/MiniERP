// CONTABILIDAD MES A MES (v0.47.0): nombres de los meses y el mes siguiente.
// El mes abierto lo decide la base de datos (erp.work_month: el primer mes abierto); aquí solo se enseña.

// «Febrero» / «February» (con mayúscula, como en la cabecera)
export function monthName(m, language = 'es') {
  const s = new Intl.DateTimeFormat(language === 'en' ? 'en-GB' : 'es-ES', { month: 'long', timeZone: 'UTC' }).format(new Date(Date.UTC(2026, m - 1, 1)))
  return s.charAt(0).toUpperCase() + s.slice(1)
}

// El mes siguiente: { year, month }
export const nextMonth = (year, month) => (month === 12 ? { year: year + 1, month: 1 } : { year, month: month + 1 })

// La fecha de inicio que propone el alta de empresa: el 1 de enero del año en curso
export const defaultStart = (today) => `${String(today).slice(0, 4)}-01-01`
