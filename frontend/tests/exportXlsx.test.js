import { describe, it, expect } from 'vitest'
import { sheetRows, fileName, excelDate } from '../src/exportXlsx.js'

describe('exportar a Excel', () => {
  const columns = [
    { header: 'Fecha', key: 'date', type: 'date' }, { header: 'Cuenta', key: 'acc', type: 'text' },
    { header: 'Debe', key: 'd', type: 'money' }, { header: 'Haber', key: 'c', type: 'money' },
  ]
  it('título, filtros, cabecera y datos; los importes son números y las fechas, fechas', () => {
    const { aoa, header } = sheetRows({ title: 'Libro diario · Demo SL', subtitle: 'Desde 2024-12-01', columns,
      rows: [{ date: '2024-12-31', acc: '57200001', d: '1210.50', c: null }] })
    expect(aoa[0]).toEqual(['Libro diario · Demo SL'])
    expect(aoa[1]).toEqual(['Desde 2024-12-01'])
    expect(header).toBe(3)
    expect(aoa[3]).toEqual(['Fecha', 'Cuenta', 'Debe', 'Haber'])
    const row = aoa[4]
    expect(row[0]).toBe(45657)                      // 31/12/2024 como número de serie de Excel
    expect(row[1]).toBe('57200001')                 // la cuenta, como texto (no pierde ceros)
    expect(row[2]).toBe(1210.5)                     // número, no "1.210,50"
    expect(row[3]).toBeNull()                       // celda vacía, no 0
  })
  it('fechas como número de serie de Excel, sin desfase por zona horaria', () => {
    expect(excelDate('1900-03-01')).toBe(61)
    expect(excelDate('2024-01-02')).toBe(45293)
    expect(excelDate('2024-01-02T23:30:00')).toBe(45293)
  })
  it('nombre de fichero sin acentos ni espacios', () => {
    expect(fileName('Balance de situación', 'Comercial Atlántico SL', 2024)).toBe('Balance_de_situacion_Comercial_Atlantico_SL_2024.xlsx')
    expect(fileName('Libro diario', 'Demo', '', null)).toBe('Libro_diario_Demo.xlsx')
  })
})
