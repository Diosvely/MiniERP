import { useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { money } from '../format'
import { readJournal } from '../importers'

const CHUNK = 2000   // filas por envío al subir el fichero

// Importar el diario completo de otro ERP (Sage, Dynamics BC o la plantilla del laboratorio) en una empresa nueva.
// 1. leer y convertir en el navegador · 2. subir por bloques · 3. vista previa con controles de auditor
// 4. importar mes a mes · 5. cerrar los ejercicios anteriores
export default function JournalImport({ onDone, onCancel }) {
  const { t, language } = useI18n()
  const [file, setFile] = useState(null)
  const [parsed, setParsed] = useState(null)      // { source, rows, digits, years }
  const [form, setForm] = useState({ name: '', territory: 'mainland', industry: 'services' })
  const [ids, setIds] = useState(null)            // { company_id, batch_id }
  const [preview, setPreview] = useState(null)
  const [progress, setProgress] = useState(null)  // { label, done, total }
  const [closings, setClosings] = useState([])
  const [finished, setFinished] = useState(false)
  const [error, setError] = useState('')

  const m = (v) => money(v, language)
  const busy = progress !== null

  async function choose(f) {
    setError(''); setParsed(null); setFile(f)
    if (!f) return
    try {
      setProgress({ label: t('importReading'), done: 0, total: 1 })
      const p = await readJournal(f)
      setParsed(p)
      setForm((x) => ({ ...x, name: f.name.replace(/\.[^.]+$/, '').replace(/^[0-9a-f]{8}-/, '') }))
    } catch (e) {
      setError(e.message)
    } finally {
      setProgress(null)
    }
  }

  // Empresa nueva + lote, y subida de las filas por bloques
  async function upload() {
    setError('')
    try {
      const { data, error } = await supabase.rpc('import_start', {
        p_name: form.name, p_digits: parsed.digits, p_territory: form.territory, p_industry: form.industry,
        p_source: parsed.source, p_file_name: file.name,
      }).single()
      if (error) throw error
      setIds(data)
      const total = parsed.rows.length
      for (let i = 0; i < total; i += CHUNK) {
        setProgress({ label: t('importUploading'), done: i, total })
        const chunk = parsed.rows.slice(i, i + CHUNK).map((r) => ({ ...r, batch_id: data.batch_id, company_id: data.company_id }))
        const { error: e2 } = await supabase.from('import_lines').insert(chunk)
        if (e2) throw e2
      }
      setProgress({ label: t('importChecking'), done: total, total })
      const p = await supabase.rpc('import_preview', { p_batch: data.batch_id })
      if (p.error) throw p.error
      setPreview(p.data)
    } catch (e) {
      setError(e.message)
    } finally {
      setProgress(null)
    }
  }

  // Preparar, contabilizar mes a mes y cerrar los ejercicios anteriores
  async function run() {
    setError('')
    try {
      setProgress({ label: t('importPreparing'), done: 0, total: 1 })
      const { data: months, error } = await supabase.rpc('import_prepare', { p_batch: ids.batch_id })
      if (error) throw error
      for (let i = 0; i < months.length; i++) {
        const mo = months[i]
        setProgress({ label: `${t('importPosting')} ${String(mo.month).padStart(2, '0')}/${mo.year}`, done: i, total: months.length })
        const { error: e2 } = await supabase.rpc('import_post_month', { p_batch: ids.batch_id, p_year: mo.year, p_month: mo.month })
        if (e2) throw e2
      }
      const done = []
      for (;;) {
        setProgress({ label: t('importClosing'), done: months.length, total: months.length })
        const { data: r, error: e3 } = await supabase.rpc('import_finish', { p_batch: ids.batch_id })
        if (e3) throw e3
        if (r.done) break
        done.push(r); setClosings([...done])
      }
      setFinished(true)
    } catch (e) {
      setError(e.message)
    } finally {
      setProgress(null)
    }
  }

  // Si el fichero no sirve: se borra la empresa creada para la prueba
  async function discard() {
    if (ids) await supabase.rpc('delete_company', { p_company: ids.company_id })
    onCancel()
  }

  const yesNo = (v) => (v ? '✓' : '—')

  return (
    <section className="tarjeta importar-diario">
      <h2>{t('importJournalTitle')}</h2>
      <p className="ayuda">{t('importJournalIntro')}</p>

      {!ids && (
        <>
          <label className="boton-archivo">
            📄 {file ? file.name : t('importChooseFile')}
            <input type="file" accept=".xlsx,.xls,.csv,.txt" hidden disabled={busy}
                   onChange={(e) => choose(e.target.files?.[0] ?? null)} />
          </label>
          <p className="ayuda">{t('importFormats')}</p>
        </>
      )}

      {parsed && !ids && (
        <>
          <ul className="comprobaciones">
            <li className="info">ℹ {t('importDetected')
              .replace('{s}', t(`importSource.${parsed.source}`)).replace('{n}', parsed.rows.length.toLocaleString(language))
              .replace('{d}', parsed.digits).replace('{y}', parsed.years.join(', '))}</li>
          </ul>
          <div className="rejilla-tres">
            <label>{t('companyName')}<input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} /></label>
            <label>{t('territoryLabel')}
              <select value={form.territory} onChange={(e) => setForm({ ...form, territory: e.target.value })}>
                {['mainland', 'canary_islands'].map((x) => <option key={x} value={x}>{t(`territory.${x}`)}</option>)}
              </select>
            </label>
            <label>{t('industryLabel')}
              <select value={form.industry} onChange={(e) => setForm({ ...form, industry: e.target.value })}>
                {['services', 'retail', 'manufacturing', 'ecommerce'].map((x) => <option key={x} value={x}>{t(`industry.${x}`)}</option>)}
              </select>
            </label>
          </div>
          <p className="ayuda">{t('importPrivateHelp')}</p>
          <div className="fila">
            <button type="button" className="secundario" disabled={busy} onClick={onCancel}>{t('cancel')}</button>
            <button type="button" disabled={busy || !form.name.trim()} onClick={upload}>{t('importUploadCheck')}</button>
          </div>
        </>
      )}

      {preview && !finished && (
        <>
          <h3>{t('importPreview')}</h3>
          <div className="tabla-ancha">
            <table className="informe">
              <thead>
                <tr>
                  <th>{t('year')}</th><th className="num">{t('importRows')}</th><th className="num">{t('entries')}</th>
                  <th className="num">{t('debit')}</th><th className="num">{t('credit')}</th>
                  <th>{t('importOpening')}</th><th>{t('importClosingPl')}</th><th>{t('importClosingEntry')}</th>
                </tr>
              </thead>
              <tbody>
                {preview.years.map((y) => (
                  <tr key={y.year}>
                    <td>{y.year}</td><td className="num">{y.rows}</td><td className="num">{y.entries}</td>
                    <td className="num">{m(y.debit)}</td><td className="num">{m(y.credit)}</td>
                    <td>{yesNo(y.has_opening)}</td><td>{yesNo(y.has_closing_pl)}</td><td>{yesNo(y.has_closing)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <h3>{t('importChecks')}</h3>
          <ul className="comprobaciones">
            {preview.errors.map((e) => (
              <li key={e.code} className="error">✕ {t(`importError.${e.code}`).replace('{d}', Array.isArray(e.detail) ? e.detail.join(', ') : e.detail ?? '')}</li>
            ))}
            {preview.negative_rows > 0 && <li className="warning">⚠ {t('importNegatives').replace('{n}', preview.negative_rows)}</li>}
            {preview.rounded_entries > 0 && <li className="warning">⚠ {t('importRounded').replace('{n}', preview.rounded_entries)}</li>}
            {preview.zero_rows > 0 && <li className="info">ℹ {t('importZeros').replace('{n}', preview.zero_rows)}</li>}
            <li className="info">ℹ {t('journalImportAccounts').replace('{n}', preview.accounts.total).replace('{m}', preview.accounts.new)}</li>
            {preview.continuity.map((c) => c.differences.length === 0 ? (
              <li key={c.year} className="info">✓ {t('importContinuityOk').replace('{y}', c.year).replace('{p}', c.year - 1)}</li>
            ) : c.differences.map((d) => (
              <li key={`${c.year}-${d.account_no}`} className={d.unregularized_result ? 'info' : 'warning'}>
                {d.unregularized_result ? 'ℹ' : '⚠'} {(d.unregularized_result ? t('importUnregularized') : t('importContinuityDiff'))
                  .replace('{y}', c.year).replace('{a}', d.account_no).replace('{c}', m(d.closing)).replace('{o}', m(d.opening))
                  .replace('{d}', m(d.difference))}
              </li>
            )))}
            {preview.years.length > 1 && !preview.years.some((y) => y.has_opening) && (
              <li className="info">ℹ {t('importNoOpenings')}</li>
            )}
          </ul>

          <div className="fila">
            <button type="button" className="secundario" disabled={busy} onClick={discard}>{t('importDiscard')}</button>
            {preview.can_import && <button type="button" disabled={busy} onClick={run}>{t('importRun')}</button>}
          </div>
        </>
      )}

      {busy && (
        <div className="progreso">
          <span>{progress.label}…</span>
          <progress value={progress.done} max={progress.total || 1} />
        </div>
      )}

      {closings.length > 0 && (
        <ul className="comprobaciones">
          {closings.map((c) => (
            <li key={c.year} className="info">🔒 {t(`importClosed.${c.closed_with}`).replace('{y}', c.year).replace('{r}', m(c.result))}</li>
          ))}
        </ul>
      )}

      {finished && (
        <>
          <p className="exito">✓ {t('journalImportDone')}</p>
          <button type="button" onClick={() => onDone(ids.company_id)}>{t('importOpenCompany')}</button>
        </>
      )}

      {error && <p className="aviso">⚠ {error}</p>}
    </section>
  )
}
