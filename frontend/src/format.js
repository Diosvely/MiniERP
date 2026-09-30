// Utilidades de formato compartidas por todas las pantallas

// Importe con 2 decimales según el idioma: 1.234,56 (es) · 1,234.56 (en)
export function money(value, language) {
  return new Intl.NumberFormat(language === 'en' ? 'en-GB' : 'es-ES', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(Number(value) || 0)
}

// Nombre de la cuenta en el idioma elegido (si no hay traducción, el nombre oficial)
export function accountName(account, language) {
  return language === 'en' ? account.name_en || account.name : account.name
}