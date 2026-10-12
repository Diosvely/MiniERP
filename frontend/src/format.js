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
//   ISP y adquisiciones intracomunitarias: "IVA 21 % · ISP" · venta del minorista en recargo: "IVA · IVA incluido (recargo)"
export function taxLabel(x, t, language) {
  const type = t(`taxType.${x.tax_type}`)
  const rate = `${Number(x.rate_pct).toLocaleString(language === 'en' ? 'en-GB' : 'es-ES')} %`
  if (['reverse_charge', 'intra_eu_acquisition'].includes(x.rate_category)) {
    return `${type} ${rate} · ${t(`taxCategory.${x.rate_category}`)}`
  }
  if (x.rate_category === 'retail_surcharge') return `${type} · ${t('taxCategory.retail_surcharge')}`
  if (Number(x.rate_pct) > 0 || !x.exemption_key) return `${type} ${rate}`
  return `${type} · ${t(`taxCategory.${x.rate_category}`)} (${x.exemption_key})`
}

// Fecha corta: 2024-01-02 → 02/01/2024 (igual en español y en inglés británico). Sin desfase de zona horaria:
// se lee el texto de la fecha, no se convierte a Date.
export function shortDate(iso) {
  if (!iso) return ''
  const [y, m, d] = String(iso).slice(0, 10).split('-')
  return `${d}/${m}/${y}`
}
