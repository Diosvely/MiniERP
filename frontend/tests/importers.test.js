import { describe, it, expect } from 'vitest'
import { readJournal } from '../src/importers.js'
import { fakeFile } from './helpers.js'

const TEMPLATE = `fecha;asiento;tipo;cuenta;nombre;debe;haber;concepto;documento
01/01/2025;1;apertura;57200001;Banco;10000,00;0;Apertura;
01/01/2025;1;apertura;10000000;Capital;0;10.000,00;Apertura;
15/01/2025;2;;60000000;Compras;1000;0;Compra;F-1
15/01/2025;2;normal;40000001;Proveedor;0;1000;Compra;F-1
31/12/2025;3;regularización;12900000;Resultado;1000;0;Regularización;
31/12/2025;3;regularizacion;60000000;Compras;0;1000;Regularización;
`

describe('readJournal · plantilla del laboratorio', () => {
  it('reconoce el formato, los dígitos y los años', async () => {
    const r = await readJournal(fakeFile('diario.csv', TEMPLATE))
    expect(r.source).toBe('template')
    expect(r.rows).toHaveLength(6)
    expect(r.digits).toBe(8)
    expect(r.years).toEqual(['2025'])
  })
  it('convierte fechas, tipos e importes con formato español', async () => {
    const { rows } = await readJournal(fakeFile('diario.csv', TEMPLATE))
    expect(rows[0]).toMatchObject({ row_no: 1, entry_date: '2025-01-01', entry_ref: '1', entry_type: 'opening', account_no: '57200001', debit: 10000, credit: 0 })
    expect(rows[1].credit).toBe(10000)                       // "10.000,00"
    expect(rows[2].entry_type).toBe('normal')                // tipo vacío = normal
    expect(rows[4].entry_type).toBe('closing_pl')            // con y sin tilde
    expect(rows[5].entry_type).toBe('closing_pl')
    expect(rows[2].document_no).toBe('F-1')
  })
  it('acepta separador coma y BOM de Excel', async () => {
    const csv = '﻿fecha,asiento,tipo,cuenta,nombre,debe,haber,concepto,documento\n2025-03-01,7,normal,57000001,Caja,12.5,0,Cobro,\n'
    const r = await readJournal(fakeFile('d.csv', csv))
    expect(r.rows[0]).toMatchObject({ entry_date: '2025-03-01', debit: 12.5, account_no: '57000001' })
  })
})

describe('readJournal · Sage y Business Central', () => {
  it('Sage: columnas en mayúscula y Tipo Asiento numérico', async () => {
    const csv = 'Fecha;Asiento;Cuenta;Nombre;Debe;Haber;Concepto;Tipo Asiento\n01/01/2024;1;572000001;Banco;500;0;Apertura;0\n01/01/2024;1;100000000;Capital;0;500;Apertura;0\n'
    const r = await readJournal(fakeFile('sage.csv', csv))
    expect(r.source).toBe('sage')
    expect(r.digits).toBe(9)
    expect(r.rows[0].entry_type).toBe('opening')
  })
  it('Business Central: importe con signo, transacción con varias fechas y regularización', async () => {
    const csv = [
      'Posting Date;Transaction No_;G_L Account No_;Amount;Description;Document No_;Source Code',
      '10/05/2023;55;570000001;-200,00;Pago;D1;',
      '12/05/2023;55;400000001;200,00;Pago;D1;',
      'C31/12/2023;90;700000001;300,00;Cierre;R1;REGULARIZACION',
      'C31/12/2023;90;129000001;-300,00;Cierre;R1;REGULARIZACION',
    ].join('\n')
    const r = await readJournal(fakeFile('bc.csv', csv))
    expect(r.source).toBe('dynamics')
    expect(r.rows[0]).toMatchObject({ debit: 0, credit: 200, entry_date: '2023-05-12' })   // la transacción va a su última fecha
    expect(r.rows[2]).toMatchObject({ entry_type: 'closing_pl', entry_date: '2023-12-31', debit: 300 })
  })
})

describe('readJournal · errores claros', () => {
  it('formato no reconocido', async () => {
    await expect(readJournal(fakeFile('x.csv', 'a;b;c\n1;2;3\n'))).rejects.toThrow(/Formato no reconocido/)
  })
  it('fichero vacío', async () => {
    await expect(readJournal(fakeFile('x.csv', 'fecha;asiento;cuenta\n'))).rejects.toThrow(/vacío/)
  })
  it('fecha que no se entiende', async () => {
    const csv = 'fecha;asiento;tipo;cuenta;nombre;debe;haber;concepto;documento\nmañana;1;normal;57200001;B;1;0;x;\n'
    await expect(readJournal(fakeFile('x.csv', csv))).rejects.toThrow(/Fecha no reconocida/)
  })
})
