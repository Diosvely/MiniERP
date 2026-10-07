// Utilidades de formato compartidas por todas las pantallas

// Importe con 2 decimales según el idioma: 1.234,56 (es) · 1,234.56 (en)
export function money(value, language) {
  return new Intl.NumberFormat(language === 'en' ? 'en-GB' : 'es-ES', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
    useGrouping: 'always',   // 2.900,00 y no 2900,00 (en español Intl no agrupa los números de 4 cifras)
  }).format(Number(value) || 0)
}

// Nombre de la cuenta en el idioma elegido (si no hay traducción, el nombre oficial)
export function accountName(account, language) {
  return language === 'en' ? account.name_en || account.name : account.name
}

// Nombre corto de un tipo de impuesto: "IVA 21 %" · sin cuota, su causa: "IVA · Exportación (E2)"
//   x = { tax_type, rate_pct, rate_category, exemption_key }
export function taxLabel(x, t, language) {
  const type = t(`taxType.${x.tax_type}`)
  if (Number(x.rate_pct) > 0 || !x.exemption_key) {
    return `${type} ${Number(x.rate_pct).toLocaleString(language === 'en' ? 'en-GB' : 'es-ES')} %`
  }
  return `${type} · ${t(`taxCategory.${x.rate_category}`)} (${x.exemption_key})`
}
