import { useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { companyPath } from '../router'
import { monthName, nextMonth } from '../monthly'
import Link from './Link'
import ErrorBox from './ErrorBox'

// CONTABILIDAD MES A MES (v0.47.0, mejora de uso 7): en la cabecera de la empresa, el mes abierto y «Cerrar mes».
// Antes de cerrar enseña lo que suele faltar (erp.month_close_preview): borradores del mes, la nómina y, al cerrar un
// trimestre, la liquidación. Si hay avisos, hay que aceptarlos. Diciembre se cierra con el Cierre del ejercicio.
// El administrador puede reabrir el último mes cerrado.
// Pantalla donde se arregla cada aviso
const SCREEN = { drafts: 'journal', payroll: 'payroll', settlement: 'settlement' }

export default function MonthBar({ company, readOnly, onChanged }) {
  const { t, language } = useI18n()
  const wm = company.work_month
  const [open, setOpen] = useState(false)
  const [preview, setPreview] = useState(null)
  const [accepted, setAccepted] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const name = (y, m) => `${monthName(m, language)} ${y}`
  const prev = wm.month > 1 ? name(wm.year, wm.month - 1) : null
  const canReopen = !readOnly && company.my_role === 'admin' && prev && (!company.start_date || company.start_date < wm.from)

  async function start() {
    setError(''); setAccepted(false); setPreview(null); setOpen(true)
    const { data, error: e } = await supabase.rpc('month_close_preview', { p_company: company.id })
    if (e) return setError(e.message)
    setPreview(data)
  }
  async function run(fn, args) {
    setBusy(true); setError('')
    const { error: e } = await supabase.rpc(fn, { p_company: company.id, ...args })
    setBusy(false)
    if (e) return setError(e.message)
    setOpen(false); onChanged?.()
  }

  const warnings = preview?.warnings ?? []
  return (
    <div className="barra-mes">
      <span className="mes-abierto" title={t('mm.help')}>📅 <strong>{name(wm.year, wm.month)}</strong></span>
      {!readOnly && !wm.december && (
        <button type="button" className="secundario" aria-expanded={open} onClick={() => (open ? setOpen(false) : start())}>{t('mm.close')}</button>)}
      {!readOnly && wm.december && <Link to={companyPath(company.id, 'closing')} className="enlace">{t('mm.december')} →</Link>}
      {wm.december && canReopen && (
        <button type="button" className="enlace" disabled={busy} onClick={() => run('reopen_month', {})}>{t('mm.reopen').replace('{m}', prev)}</button>)}
      {!open && error && <ErrorBox error={error} company={company} />}
      {open && (
        <div className="panel-mes" role="dialog" aria-label={t('mm.closeTitle').replace('{m}', name(wm.year, wm.month))}>
          <h3>{t('mm.closeTitle').replace('{m}', name(wm.year, wm.month))}</h3>
          {!preview && !error && <p className="ayuda">{t('loadingData')}…</p>}
          {preview && (
            <>
              <p className="ayuda">{t('mm.closeHelp').replace('{n}', preview.entries).replace('{next}', name(nextMonth(wm.year, wm.month).year, nextMonth(wm.year, wm.month).month))}</p>
              {warnings.length === 0 && <p className="exito">✓ {t('mm.noWarnings')}</p>}
              {warnings.length > 0 && (
                <ul className="avisos-mes">
                  {warnings.map((w) => (
                    <li key={w.code}>⚠ {t(`mm.warn.${w.code}`).replace('{n}', w.count ?? '').replace('{q}', w.quarter ?? '').replace('{tax}', w.tax === 'IGIC' ? 'IGIC' : 'IVA')}{' '}
                      <Link to={companyPath(company.id, SCREEN[w.code])} className="enlace">{t('err.goTo')} {t(`nav.${SCREEN[w.code]}.label`).replace('{tax}', w.tax === 'IGIC' ? 'IGIC' : 'IVA')} →</Link>
                    </li>))}
                </ul>)}
              {warnings.length > 0 && (
                <label className="opcion">
                  <input type="checkbox" checked={accepted} onChange={(e) => setAccepted(e.target.checked)} /> {t('mm.accept')}
                </label>)}
              <div className="fila-botones">
                <button type="button" disabled={busy || (warnings.length > 0 && !accepted)}
                        onClick={() => run('close_month', { p_accept_warnings: accepted })}>
                  {t('mm.closeButton').replace('{m}', monthName(wm.month, language))}
                </button>
                <button type="button" className="secundario" onClick={() => setOpen(false)}>{t('cancel')}</button>
              </div>
            </>)}
          {canReopen && (
            <p className="ayuda">{t('mm.reopenHelp')}{' '}
              <button type="button" className="enlace" disabled={busy} onClick={() => run('reopen_month', {})}>
                {t('mm.reopen').replace('{m}', prev)}
              </button>
            </p>)}
          <ErrorBox error={error} company={company} />
        </div>
      )}
    </div>
  )
}
