import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { money } from '../format'

// Cierre del ejercicio en 4 pasos, como el asistente de cierre de A3 / Sage / ContaPlus
//   (BC: "Close Income Statement" + cerrar el año · SAP: FAGLGVTR "Balance Carryforward")
export default function YearClosing({ company, readOnly }) {
  const { t, language } = useI18n()
  const [years, setYears] = useState([])
  const [year, setYear] = useState(null)
  const [data, setData] = useState(null)
  const [history, setHistory] = useState([])
  const [accept, setAccept] = useState(false)
  const [confirming, setConfirming] = useState(null)   // 'close' | 'reopen'
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')

  const m = (v) => money(v, language)
  const isAdmin = !readOnly && company.my_role === 'admin'

  async function loadYears(keep) {
    const { data, error } = await supabase.from('fiscal_years').select('year, status')
      .eq('company_id', company.id).order('year')
    if (error) return setError(error.message)
    setYears(data)
    // Por defecto, el ejercicio abierto más antiguo: los ejercicios se cierran en orden
    if (!keep) setYear(data.find((y) => y.status === 'open')?.year ?? data[data.length - 1]?.year ?? null)
  }

  async function load() {
    if (!year) return
    const [p, h] = await Promise.all([
      supabase.rpc('year_closing_preview', { p_company: company.id, p_year: Number(year) }),
      supabase.from('v_year_closings').select('*').eq('company_id', company.id)
        .order('year', { ascending: false }).order('created_at', { ascending: false }),
    ])
    if (p.error) { setData(null); setError(p.error.message) } else { setError(''); setData(p.data) }
    if (!h.error) setHistory(h.data)
  }

  useEffect(() => { loadYears(false) }, [company.id])
  useEffect(() => { setAccept(false); setConfirming(null); load() }, [year])

  async function run(fn, args, okText) {
    setError(''); setMessage(''); setBusy(true)
    const { error } = await supabase.rpc(fn, args)
    setBusy(false); setConfirming(null)
    if (error) return setError(error.message)
    setMessage(okText)
    await loadYears(true)
    load()
  }

  const close = () => run('close_fiscal_year',
    { p_company: company.id, p_year: Number(year), p_accept_warnings: accept },
    t('yearClosedMsg').replace('{y}', year))
  const reopen = () => run('reopen_fiscal_year',
    { p_company: company.id, p_year: Number(year) },
    t('yearReopenedMsg').replace('{y}', year))

  if (years.length === 0) {
    return <section className="tarjeta"><h2>{t('yearClosingTitle')}</h2><p>{t('noFiscalYears')}</p></section>
  }

  const checks = data?.checks ?? []
  const result = Number(data?.result ?? 0)
  const icon = { error: '✕', warning: '⚠', info: 'ℹ' }
  const linesTable = (lines, swap) => (
    <div className="tabla-scroll">
      <table>
        <thead><tr><th>{t('account')}</th><th className="num">{t('debit')}</th><th className="num">{t('credit')}</th></tr></thead>
        <tbody>
          {lines.map((l) => {
            const [d, c] = swap ? [l.credit, l.debit] : [l.debit, l.credit]
            return (
              <tr key={l.account_no}>
                <td><span className="codigo">{l.account_no}</span> {l.account_name}</td>
                <td className="num">{Number(d) ? m(d) : ''}</td>
                <td className="num">{Number(c) ? m(c) : ''}</td>
              </tr>
            )
          })}
        </tbody>
      </table>
    </div>
  )

  return (
    <>
      <section className="tarjeta">
        <h2>{t('yearClosingTitle')}</h2>
        <p className="ayuda">{t('yearClosingIntro')}</p>
        <label className="ejercicio-cierre">{t('year')}
          <select value={year ?? ''} onChange={(e) => setYear(e.target.value)}>
            {years.map((y) => (
              <option key={y.year} value={y.year}>{y.year} · {t(`fiscalYearStatus.${y.status}`)}</option>
            ))}
          </select>
        </label>
        {error && <p className="aviso">⚠ {error}</p>}
        {message && <p className="exito">✓ {message}</p>}
      </section>

      {data && (
        <section className="tarjeta cierre">
          <h2>
            {t('fiscalYear')} {data.year}{' '}
            <span className={data.closed ? 'insignia cerrado' : 'insignia'}>{t(`fiscalYearStatus.${data.status}`)}</span>
          </h2>

          {/* Resultado del ejercicio: lo que la regularización lleva a la 129 */}
          <div className={result >= 0 ? 'cuadre ok' : 'cuadre descuadre'}>
            <span>{t('yearResult')} ({data.result_account_no})</span>
            <strong>{result >= 0 ? t('profit') : t('loss')}: {m(Math.abs(result))}</strong>
          </div>

          {data.closed ? (
            <>
              <p className="exito">✓ {t('yearIsClosed')
                .replace('{a}', data.entries?.closing_pl ?? '—')
                .replace('{b}', data.entries?.closing ?? '—')
                .replace('{c}', data.entries?.opening ?? '—')
                .replace('{y}', Number(data.year) + 1)}</p>
              <p className="ayuda">{t('reopenHelp')}</p>
              {isAdmin && data.can_reopen && confirming !== 'reopen' && (
                <button type="button" className="secundario" onClick={() => setConfirming('reopen')}>↩ {t('reopenYear')}</button>
              )}
              {isAdmin && !data.can_reopen && <p className="ayuda">{t('reopenNextFirst').replace('{y}', Number(data.year) + 1)}</p>}
              {confirming === 'reopen' && (
                <div className="anular">
                  <p>{t('confirmReopen').replace('{y}', data.year)}</p>
                  <div className="fila">
                    <button type="button" className="secundario" onClick={() => setConfirming(null)}>{t('cancel')}</button>
                    <button type="button" disabled={busy} onClick={reopen}>{t('reopenYear')}</button>
                  </div>
                </div>
              )}
            </>
          ) : (
            <>
              <ol className="pasos-cierre">
                <li>
                  <h3>{t('closingStep1')}</h3>
                  {checks.filter((c) => c.severity !== 'info').length === 0 && <p className="exito">✓ {t('allChecksOk')}</p>}
                  <ul className="comprobaciones">
                    {checks.map((c) => (
                      <li key={c.code} className={c.severity}>
                        <span className="icono">{icon[c.severity]}</span> {t(`check.${c.code}`).replace('{d}', c.detail)}
                      </li>
                    ))}
                  </ul>
                </li>
                <li>
                  <h3>{t('closingStep2')} · {data.closing_date}</h3>
                  <p className="ayuda">{t('closingPlHelp')}</p>
                  {data.closing_pl_lines.length === 0 ? <p className="ayuda">{t('noLinesToClose')}</p> : (
                    <details>
                      <summary>{t('seeEntryLines').replace('{n}', data.closing_pl_lines.length)}</summary>
                      {linesTable(data.closing_pl_lines)}
                    </details>
                  )}
                </li>
                <li>
                  <h3>{t('closingStep3')} · {data.closing_date}</h3>
                  <p className="ayuda">{t('closingHelp')}</p>
                  {data.closing_lines.length === 0 ? <p className="ayuda">{t('noLinesToClose')}</p> : (
                    <details>
                      <summary>{t('seeEntryLines').replace('{n}', data.closing_lines.length)}</summary>
                      {linesTable(data.closing_lines)}
                    </details>
                  )}
                </li>
                <li>
                  <h3>{t('closingStep4')} · {data.opening_date}</h3>
                  <p className="ayuda">{t('openingHelp').replace('{y}', Number(data.year) + 1)}</p>
                  {data.closing_lines.length > 0 && (
                    <details>
                      <summary>{t('seeEntryLines').replace('{n}', data.closing_lines.length)}</summary>
                      {linesTable(data.closing_lines, true)}
                    </details>
                  )}
                </li>
              </ol>

              {!isAdmin && <p className="ayuda">{t('onlyAdminCloses')}</p>}
              {isAdmin && data.can_close && data.has_warnings && (
                <label className="opcion">
                  <input type="checkbox" checked={accept} onChange={(e) => setAccept(e.target.checked)} /> {t('acceptWarnings')}
                </label>
              )}
              {isAdmin && confirming !== 'close' && (
                <button type="button" disabled={!data.can_close || (data.has_warnings && !accept)}
                        onClick={() => setConfirming('close')}>
                  🔒 {t('closeYear').replace('{y}', data.year)}
                </button>
              )}
              {confirming === 'close' && (
                <div className="anular">
                  <p>{t('confirmClose').replace('{y}', data.year).replace('{y2}', Number(data.year) + 1)}</p>
                  <div className="fila">
                    <button type="button" className="secundario" onClick={() => setConfirming(null)}>{t('cancel')}</button>
                    <button type="button" disabled={busy} onClick={close}>🔒 {t('closeYear').replace('{y}', data.year)}</button>
                  </div>
                </div>
              )}
            </>
          )}
        </section>
      )}

      <section className="tarjeta">
        <h2>{t('closingHistory')}</h2>
        {history.length === 0 && <p>{t('noClosings')}</p>}
        <ul>
          {history.map((h) => (
            <li key={h.id} className={h.status === 'cancelled' ? 'bloqueado' : ''}>
              <strong>{t('fiscalYear')} {h.year}</strong>
              <span>
                {Number(h.result) >= 0 ? t('profit') : t('loss')} {m(Math.abs(h.result))}
                {' · '}{t('entries')} {h.closing_pl_no ?? '—'}, {h.closing_no ?? '—'} · {t('openingShort')} {h.opening_no ?? '—'}
                {h.status === 'cancelled' && ` · ${t('reopened')}`}
              </span>
            </li>
          ))}
        </ul>
      </section>
    </>
  )
}
