import { useState } from 'react'
import { useI18n } from '../i18n'
import { FileSpreadsheet, Printer } from 'lucide-react'
import { ICON } from '../icons'

// Botones de un informe: Excel e Imprimir (o guardar en PDF desde el cuadro de impresión del navegador)
//   onExcel: función que genera el fichero · info: empresa y filtros, que solo se ven en la hoja impresa
export default function ReportActions({ onExcel, info }) {
  const { t } = useI18n()
  const [busy, setBusy] = useState(false)
  async function excel() {
    setBusy(true)
    try { await onExcel() } finally { setBusy(false) }
  }
  return (
    <>
      <div className="acciones-informe">
        <button type="button" className="secundario" disabled={busy} onClick={excel}>
          <FileSpreadsheet {...ICON} /> {busy ? `${t('loadingData')}…` : t('exportExcel')}
        </button>
        <button type="button" className="secundario" onClick={() => window.print()}>
          <Printer {...ICON} /> {t('print')}
        </button>
      </div>
      {info && <p className="solo-impresion">{info}</p>}
    </>
  )
}
