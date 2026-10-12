// EXPORTAR A EXCEL los informes (Balance, PyG, EFE, sumas y saldos, mayor, diario)
// Los importes van como NÚMEROS con formato #.##0,00 (no como texto): en Excel se pueden sumar, filtrar y llevar a una
// tabla dinámica o a Power BI. Las fechas, como fechas. Encima de la tabla: título, empresa y filtros, como en un
// informe de Business Central exportado a Excel.
// La librería xlsx (SheetJS) solo se descarga cuando alguien pulsa "Excel".

//   columns: [{ header, key, type: 'text' | 'money' | 'date' | 'int' | 'pct', width }]
//   rows:    [{ [key]: valor }]
// → { aoa: filas para la hoja (array de arrays), header: nº de fila de la cabecera (0-based) }
export function sheetRows({ title, subtitle, columns, rows }) {
  const aoa = [[title], [subtitle ?? ''], [], columns.map((c) => c.header)]
  for (const r of rows) {
    aoa.push(columns.map((c) => {
      const v = r[c.key]
      if (v == null || v === '') return null
      if (c.type === 'money' || c.type === 'int' || c.type === 'pct') return Number(v)
      if (c.type === 'date') return excelDate(v)
      return String(v)
    }))
  }
  return { aoa, header: 3 }
}

// Fecha → número de serie de Excel (días desde el 30/12/1899), con formato dd/mm/aaaa al escribirla.
// Así no depende de la zona horaria del navegador (con objetos Date, SheetJS desplazaba algunos días).
export function excelDate(iso) {
  const [y, m, d] = String(iso).slice(0, 10).split('-').map(Number)
  return (Date.UTC(y, m - 1, d) - Date.UTC(1899, 11, 30)) / 86400000
}

// Nombre de fichero seguro: "Balance · Empresa SL · 2024" → "Balance_Empresa_SL_2024.xlsx"
export function fileName(...parts) {
  return `${parts.filter(Boolean).join(' ').normalize('NFD').replace(/[̀-ͯ]/g, '')
    .replace(/[^\w.-]+/g, '_').replace(/_+/g, '_').replace(/^_|_$/g, '')}.xlsx`
}

export async function downloadXlsx({ title, subtitle, sheet, columns, rows, file }) {
  const XLSX = await import('xlsx')
  const { aoa, header } = sheetRows({ title, subtitle, columns, rows })
  const ws = XLSX.utils.aoa_to_sheet(aoa)
  const formats = { money: '#,##0.00;[Red]-#,##0.00', int: '0', pct: '0.0%', date: 'dd/mm/yyyy' }
  columns.forEach((c, ci) => {
    if (!formats[c.type]) return
    for (let ri = header + 1; ri < aoa.length; ri++) {
      const cell = ws[XLSX.utils.encode_cell({ r: ri, c: ci })]
      if (cell) cell.z = formats[c.type]
    }
  })
  ws['!cols'] = columns.map((c) => ({ wch: c.width ?? (c.type === 'text' ? 40 : 14) }))
  ws['!autofilter'] = { ref: XLSX.utils.encode_range({ r: header, c: 0 }, { r: aoa.length - 1, c: columns.length - 1 }) }
  const wb = XLSX.utils.book_new()
  XLSX.utils.book_append_sheet(wb, ws, (sheet ?? 'Datos').slice(0, 31))
  XLSX.writeFile(wb, file)
}
