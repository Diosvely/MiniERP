// Lectura de archivos CSV exportados desde Excel (reutilizable: subcuentas, asientos, terceros…)

// Lee el archivo como texto. Excel guarda en UTF-8 ("CSV UTF-8") o en Windows-1252 ("CSV delimitado"):
// probamos UTF-8 y, si hay caracteres inválidos, usamos Windows-1252 para no romper tildes y eñes.
export async function readTextFile(file) {
  const buffer = await file.arrayBuffer()
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(buffer)
  } catch {
    return new TextDecoder('windows-1252').decode(buffer)
  }
}

// Convierte el texto CSV en una lista de objetos { columna: valor }
//  - quita la marca invisible BOM que añade Excel al principio
//  - detecta el separador: punto y coma (Excel en español) o coma
//  - respeta valores entre comillas, que pueden contener el separador
export function parseCsv(text) {
  text = text.replace(/^\uFEFF/, '')
  const firstLine = text.split(/\r?\n/, 1)[0] ?? ''
  const count = (ch) => firstLine.split(ch).length - 1
  const delimiter = count(';') >= count(',') ? ';' : ','

  const rows = []
  let row = []
  let field = ''
  let quoted = false
  for (let i = 0; i < text.length; i++) {
    const ch = text[i]
    if (quoted) {
      if (ch === '"' && text[i + 1] === '"') { field += '"'; i++ }
      else if (ch === '"') quoted = false
      else field += ch
    } else if (ch === '"') quoted = true
    else if (ch === delimiter) { row.push(field); field = '' }
    else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && text[i + 1] === '\n') i++
      row.push(field); rows.push(row); row = []; field = ''
    } else field += ch
  }
  if (field !== '' || row.length) { row.push(field); rows.push(row) }

  const [header = [], ...data] = rows.filter((r) => r.some((c) => c.trim() !== ''))
  const keys = header.map((h) => h.trim().toLowerCase())
  return data.map((r) => Object.fromEntries(keys.map((k, i) => [k, (r[i] ?? '').trim()])))
}

// Descarga un CSV (con BOM para que Excel lo abra con tildes correctas)
export function downloadCsv(filename, lines) {
  const blob = new Blob(['\uFEFF' + lines.join('\r\n') + '\r\n'], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}