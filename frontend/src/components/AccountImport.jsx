import { useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { readTextFile, parseCsv, downloadCsv } from '../csv'

// Nombres de columna aceptados en el CSV (español o inglés). La columna "grupo" se ignora:
// la base de datos ya sabe a qué grupo pertenece cada subcuenta.
const COLUMNS = {
  account_no: ['subcuenta', 'account_no', 'cuenta', 'account'],
  name: ['nombre_es', 'name', 'nombre'],
  name_en: ['nombre_en', 'name_en'],
}
const pick = (row, aliases) => aliases.map((a) => row[a]).find((v) => v !== undefined) ?? ''

// Importación de subcuentas: cargar CSV → vista previa validada por la base de datos → importar
export default function AccountImport({ company, onImported }) {
  const { t } = useI18n()
  const [rows, setRows] = useState([])        // filas leídas del archivo
  const [preview, setPreview] = useState([])  // resultado de la validación (dry run)
  const [fileName, setFileName] = useState('')
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)

  function reset() {
    setRows([]); setPreview([]); setFileName('')
  }

  async function onFile(e) {
    const file = e.target.files?.[0]
    e.target.value = ''   // permite volver a elegir el mismo archivo
    if (!file) return
    setError(''); setMessage(''); reset()

    const data = parseCsv(await readTextFile(file))
    if (data.length === 0 || !COLUMNS.account_no.some((c) => c in data[0])) {
      return setError(t('csvMissingColumns'))
    }
    const mapped = data.map((r) => ({
      account_no: pick(r, COLUMNS.account_no),
      name: pick(r, COLUMNS.name),
      name_en: pick(r, COLUMNS.name_en),
    }))
    setFileName(file.name)
    setRows(mapped)

    // Vista previa: la base de datos valida cada fila sin guardar nada
    setBusy(true)
    const { data: result, error } = await supabase.rpc('import_posting_accounts', {
      p_company: company.id, p_rows: mapped, p_dry_run: true,
    })
    setBusy(false)
    if (error) return setError(error.message)
    setPreview(result)
  }

  async function runImport() {
    setBusy(true); setError('')
    const { error } = await supabase.rpc('import_posting_accounts', {
      p_company: company.id, p_rows: rows, p_dry_run: false,
    })
    setBusy(false)
    if (error) return setError(error.message)
    setMessage(t('importDone').replace('{n}', rows.length))
    reset()
    onImported?.()
  }

  function downloadTemplate() {
    downloadCsv('plantilla_subcuentas.csv', [
      'grupo;subcuenta;nombre_es;nombre_en',
      '1;10000000;Capital social;Share capital',
      '4;43000001;Cliente 1;Customer 1',
      '5;57200001;Banco 1;Bank 1',
    ])
  }

  const count = (s) => preview.filter((p) => p.status === s).length
  const errors = count('error')

  return (
    <section className="tarjeta">
      <h2>{t('importAccounts')}</h2>
      <p className="ayuda">{t('importHelp').replace('{n}', company.posting_account_digits)}</p>
      <div className="fila">
        <label className="boton-archivo">
          📄 {t('chooseCsv')}
          <input type="file" accept=".csv,text/csv" onChange={onFile} hidden />
        </label>
        <button type="button" className="secundario" onClick={downloadTemplate}>⬇ {t('downloadTemplate')}</button>
      </div>

      {busy && <p className="ayuda">⏳ {t('validating')}</p>}

      {preview.length > 0 && (
        <>
          <p>
            <strong>{fileName}</strong> · {t('importNew')}: {count('insert')} · {t('importUpdate')}: {count('update')} ·{' '}
            <span className={errors ? 'aviso' : ''}>{t('importErrors')}: {errors}</span>
          </p>
          <div className="tabla-scroll">
            <table>
              <thead>
                <tr><th>#</th><th>{t('accountNo')}</th><th>{t('companyName')}</th><th>{t('status')}</th></tr>
              </thead>
              <tbody>
                {preview.map((p) => (
                  <tr key={p.line_no} className={`estado-${p.status}`}>
                    <td>{p.line_no}</td>
                    <td className="codigo">{p.account_no}</td>
                    <td>{p.name}</td>
                    <td>
                      <strong>{t(`importStatus.${p.status}`)}</strong>
                      <br /><small>{p.message}</small>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="fila">
            <button type="button" className="secundario" onClick={reset}>{t('cancel')}</button>
            <button type="button" disabled={busy || errors > 0} onClick={runImport}>
              {t('importNow').replace('{n}', rows.length)}
            </button>
          </div>
          {errors > 0 && <p className="aviso">{t('fixErrors')}</p>}
        </>
      )}

      {error && <p className="aviso">⚠ {error}</p>}
      {message && <p className="exito">✓ {message}</p>}
    </section>
  )
}