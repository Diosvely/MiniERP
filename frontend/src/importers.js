// Convertidores de diarios de otros ERP a la PLANTILLA DEL LABORATORIO (una fila por apunte):
//   { entry_date: 'AAAA-MM-DD', entry_ref, entry_type: opening|normal|closing_pl|closing,
//     account_no, account_name, debit, credit, description, document_no }
// Como los "paquetes de configuración" de Business Central: cada origen tiene su traducción a un formato común.

const TYPES = { 0: 'opening', 1: 'normal', 2: 'closing_pl', 3: 'closing' }
const TEMPLATE_TYPES = {
  apertura: 'opening', opening: 'opening', normal: 'normal',
  regularizacion: 'closing_pl', 'regularización': 'closing_pl', closing_pl: 'closing_pl',
  cierre: 'closing', closing: 'closing',
}

// "1.234,56" · "1234,56" · "1234.56" · 1234.56 → 1234.56
const num = (v) => {
  if (v == null || v === '') return 0
  if (typeof v === 'number') return Math.round(v * 100) / 100
  let s = String(v).trim()
  if (s.includes(',')) s = s.replace(/\./g, '').replace(',', '.')
  const n = Number(s)
  return Number.isFinite(n) ? Math.round(n * 100) / 100 : 0
}
const pad = (n) => String(n).padStart(2, '0')
// Date de Excel · "dd/mm/aaaa" · "aaaa-mm-dd" → "aaaa-mm-dd"
const isoDate = (v) => {
  if (v instanceof Date) {
    // Excel guarda la fecha como número de días: se redondea al día (± zona horaria y segundos sueltos)
    const d = new Date(v.getTime() + 12 * 3600 * 1000)
    return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`
  }
  const s = String(v ?? '').trim().replace(/^C/, '')        // BC: fecha de cierre "C31/12/2023"
  let m = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})/)
  if (m) return `${m[3]}-${pad(m[2])}-${pad(m[1])}`
  m = s.match(/^(\d{4})-(\d{2})-(\d{2})/)
  if (m) return `${m[1]}-${m[2]}-${m[3]}`
  throw new Error(`Fecha no reconocida: "${s}"`)
}

// CSV con ; o , (sin comillas complejas): primera fila = cabecera
function parseCsv(text) {
  const lines = text.split(/\r?\n/).filter((l) => l.trim() !== '')
  const sep = (lines[0].match(/;/g) ?? []).length >= (lines[0].match(/,/g) ?? []).length ? ';' : ','
  const clean = (c) => c.trim().replace(/^"(.*)"$/, '$1')
  const header = lines[0].split(sep).map(clean)
  return lines.slice(1).map((l) => {
    const cells = l.split(sep).map(clean)
    return Object.fromEntries(header.map((h, i) => [h, cells[i] ?? '']))
  })
}

// ---------------------------------------------------------------------------
// Sage (y A3 / ContaPlus con las mismas columnas): Fecha, Asiento, Cuenta, Nombre, Debe, Haber, Concepto, Tipo Asiento
// ---------------------------------------------------------------------------
function fromSage(rows) {
  return rows.map((r) => ({
    entry_date: isoDate(r.Fecha),
    entry_ref: String(r.Asiento),
    entry_type: TYPES[Number(r['Tipo Asiento'] ?? 1)] ?? 'normal',
    account_no: String(r.Cuenta).trim(),
    account_name: String(r.Nombre ?? '').trim(),
    debit: num(r.Debe),
    credit: num(r.Haber),
    description: String(r.Concepto ?? '').trim(),
    document_no: '',
  }))
}

// ---------------------------------------------------------------------------
// Dynamics 365 Business Central: movimientos de contabilidad (tabla G/L Entry)
//   · importe con signo en "Amount" (Debit/Credit Amount no son fiables en las exportaciones)
//   · asiento = "Transaction No_"; una transacción con varias fechas (periodificaciones) va a su última fecha
//   · "Asiento de regularización" (o Prior-Year Entry) = regularización, a 31/12
//   · BC no tiene asientos de apertura ni de cierre: los genera nuestro cierre del ejercicio
// ---------------------------------------------------------------------------
function fromDynamics(rows) {
  const last = {}
  for (const r of rows) {
    const d = isoDate(r['Posting Date'])
    const t = r['Transaction No_']
    if (!last[t] || d > last[t]) last[t] = d
  }
  return rows.map((r) => {
    const amount = num(r.Amount)
    const closing = (r['Source Code'] ?? '').toLowerCase().includes('regulariz')
    const date = last[r['Transaction No_']]
    return {
      entry_date: closing ? `${date.slice(0, 4)}-12-31` : date,
      entry_ref: String(r['Transaction No_']),
      entry_type: closing ? 'closing_pl' : 'normal',
      account_no: String(r['G_L Account No_']).trim(),
      account_name: '',
      debit: amount > 0 ? amount : 0,
      credit: amount < 0 ? -amount : 0,
      description: String(r.Description_ ?? r.Description ?? '').trim(),
      document_no: String(r['Document No_'] ?? '').trim(),
    }
  })
}

// ---------------------------------------------------------------------------
// Plantilla del laboratorio (CSV o Excel): fecha, asiento, tipo, cuenta, nombre, debe, haber, concepto, documento
// ---------------------------------------------------------------------------
function fromTemplate(rows) {
  return rows.map((r) => ({
    entry_date: isoDate(r.fecha),
    entry_ref: String(r.asiento),
    entry_type: TEMPLATE_TYPES[String(r.tipo ?? 'normal').trim().toLowerCase()] ?? 'normal',
    account_no: String(r.cuenta).trim(),
    account_name: String(r.nombre ?? '').trim(),
    debit: num(r.debe),
    credit: num(r.haber),
    description: String(r.concepto ?? '').trim(),
    document_no: String(r.documento ?? '').trim(),
  }))
}

// Lee el fichero, reconoce el origen y lo convierte. Devuelve { source, rows, digits, years }
export async function readJournal(file) {
  let raw
  if (/\.xlsx?$/i.test(file.name)) {
    const XLSX = await import('xlsx')                       // solo se descarga si hace falta
    const wb = XLSX.read(await file.arrayBuffer(), { cellDates: true })
    const sheet = wb.Sheets.Diario ?? wb.Sheets[wb.SheetNames[0]]
    raw = XLSX.utils.sheet_to_json(sheet, { defval: '' })
      .map((r) => Object.fromEntries(Object.entries(r).map(([k, v]) => [k.trim(), v])))   // " Debe " → "Debe"
  } else {
    const buf = await file.arrayBuffer()
    let text = new TextDecoder('utf-8', { fatal: false }).decode(buf)
    if (text.includes('�')) text = new TextDecoder('windows-1252').decode(buf)   // exportaciones en ANSI
        raw = parseCsv(text.replace(/^\uFEFF/, ''))
  }
  if (raw.length === 0) throw new Error('El fichero está vacío')

  const cols = Object.keys(raw[0])
  const source = cols.includes('G_L Account No_') ? 'dynamics'
    : cols.includes('Asiento') && cols.includes('Cuenta') ? 'sage'
    : cols.includes('asiento') && cols.includes('cuenta') ? 'template'
    : null
  if (!source) throw new Error(`Formato no reconocido. Columnas: ${cols.slice(0, 8).join(', ')}…`)

  const rows = (source === 'dynamics' ? fromDynamics(raw) : source === 'sage' ? fromSage(raw) : fromTemplate(raw))
    .map((r, i) => ({ row_no: i + 1, ...r }))

  // Dígitos de las subcuentas: la longitud más frecuente
  const lengths = {}
  for (const r of rows) lengths[r.account_no.length] = (lengths[r.account_no.length] ?? 0) + 1
  const digits = Number(Object.entries(lengths).sort((a, b) => b[1] - a[1])[0][0])
  const years = [...new Set(rows.map((r) => r.entry_date.slice(0, 4)))].sort()
  return { source, rows, digits, years }
}
