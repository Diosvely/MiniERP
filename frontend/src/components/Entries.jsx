import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { money } from '../format'
import { companyPath, navigate } from '../router'
import { showDate } from '../quickDate'
import { workDate } from '../workDate'
import { monthName } from '../monthly'
import { PAGE, RANGES, filterEntries, monthRange, rangeDates, rowTarget, saveRange, savedRange, selectable, sourcesOf, summary } from '../entries'
import { downloadXlsx, fileName } from '../exportXlsx'
import DateField from './DateField'
import Link from './Link'
import ErrorBox from './ErrorBox'
import ReportActions from './ReportActions'
import { Trash2 } from 'lucide-react'

const ICON = { posted: '✓', ok: '✎', error: '✕' }

// ASIENTOS (v0.47.0, mejora de uso 9): la pantalla principal de Contabilidad, como la gestión de asientos de ContaSol.
// Una fila por asiento con su origen y su estado (contabilizado · en edición · con error), coloreada muy suave.
// Fechas con tres botones (Mes actual · Desde / hasta · Todos), más filtros de estado, origen y texto.
// Un clic abre el asiento: el contabilizado, su ficha; el borrador, en Nuevo asiento para seguir con él.
// Los borradores «en edición» se pueden marcar y contabilizar de una vez (erp.post_entries); un borrador se puede borrar.
export default function Entries({ company, readOnly, refreshKey }) {
  const { t, language } = useI18n()
  const [range, setRange] = useState(savedRange)
  const [dates, setDates] = useState(() => ({ from: '', to: '' }))
  const [rows, setRows] = useState(null)
  const [total, setTotal] = useState(0)
  const [filters, setFilters] = useState({ state: '', source: '', text: '' })
  const [checked, setChecked] = useState([])
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [confirmDelete, setConfirmDelete] = useState(null)
  const [busy, setBusy] = useState(false)
  const [reload, setReload] = useState(0)
  const wd = workDate(company)
  const cur = monthRange(wd, company.work_month).from   // el mes del botón «Mes actual»
  const monthLabel = `${monthName(Number(cur.slice(5, 7)), language)} ${cur.slice(0, 4)}`
  const q = rangeDates(range, { workDate: wd, workMonth: company.work_month, ...dates })

  async function fetchPage(offset) {
    const { data, error: e } = await supabase.rpc('entries_list', { p_company: company.id, p_from: q.from, p_to: q.to, p_limit: PAGE, p_offset: offset })
    if (e) { setError(e.code === 'PGRST202' ? t('ent.dbMissing') : e.message); return null }
    setError('')
    setTotal(data?.[0]?.total_count ?? 0)
    return data ?? []
  }
  useEffect(() => {
    let alive = true
    fetchPage(0).then((d) => { if (alive && d) { setRows(d); setChecked([]) } })
    return () => { alive = false }
  }, [company.id, range, q.from, q.to, refreshKey, reload])   // eslint-disable-line react-hooks/exhaustive-deps

  const choose = (r) => { setRange(r); saveRange(r) }
  const list = filterEntries(rows, filters)
  const s = summary(list)
  const sources = sourcesOf(rows)
  const sel = list.filter((r) => checked.includes(r.entry_id))
  const to = (section) => companyPath(company.id, section)

  async function postSelected() {
    setBusy(true); setMessage(''); setError('')
    const { data, error: e } = await supabase.rpc('post_entries', { p_company: company.id, p_entries: checked })
    setBusy(false)
    if (e) return setError(e.message)
    const failed = data?.failed ?? []
    setMessage(t('ent.posted').replace('{n}', data?.posted?.length ?? 0) + (failed.length ? ' ' + t('ent.notPosted').replace('{n}', failed.length) : ''))
    setReload((x) => x + 1)
  }
  async function remove(id) {
    setConfirmDelete(null); setError('')
    const { error: e } = await supabase.rpc('delete_draft', { p_entry: id })
    if (e) return setError(e.message)
    setMessage(t('ent.deleted')); setReload((x) => x + 1)
  }
  async function more() {
    const d = await fetchPage(rows.length)
    if (d) setRows([...rows, ...d])
  }
  const exportExcel = () => downloadXlsx({
    title: `${t('nav.entries.label')} · ${company.name ?? ''}`, subtitle: q.from || q.to ? `${showDate(q.from) || '…'} – ${showDate(q.to) || '…'}` : t('ent.range.all'),
    sheet: t('nav.entries.label'), file: fileName(t('nav.entries.label'), company.name, q.from?.slice(0, 7) ?? ''),
    columns: [{ header: t('ent.col.no'), key: 'entry_no', type: 'int' }, { header: t('ent.col.date'), key: 'posting_date', type: 'date' },
      { header: t('ent.col.doc'), key: 'document_no', type: 'text' }, { header: t('ent.col.concept'), key: 'description', type: 'text', width: 50 },
      { header: t('ent.col.debit'), key: 'total_debit', type: 'money' }, { header: t('ent.col.credit'), key: 'total_credit', type: 'money' },
      { header: t('ent.col.source'), key: 'origin', type: 'text', width: 22 }, { header: t('ent.col.state'), key: 'stateText', type: 'text', width: 30 }],
    rows: list.map((r) => ({ ...r, origin: t(`ent.source.${r.source}`), stateText: t(`ent.state.${r.state}`) + (r.problem ? ` · ${t(`ent.problem.${r.problem}`)}` : '') })),
  })

  return (
    <>
      <section className="tarjeta">
        <div className="titulo-modelo">
          <h2>{t('nav.entries.label')}</h2>
          {!readOnly && <Link to={to('entry')} className="boton-enlace">+ {t('newEntry')}</Link>}
        </div>
        <div className="botones-rango" role="group" aria-label={t('ent.rangeLabel')}>
          {RANGES.map((r) => (
            <button key={r} type="button" className={range === r ? 'activo' : 'secundario'} aria-pressed={range === r} onClick={() => choose(r)}>
              {t(`ent.range.${r}`)}{r === 'month' && ` · ${monthLabel}`}
            </button>))}
        </div>
        {range === 'range' && (
          <div className="rejilla-tres">
            <label htmlFor="asientos-desde">{t('ent.from')}<DateField id="asientos-desde" value={dates.from} company={company} onChange={(d) => setDates((x) => ({ ...x, from: d }))} /></label>
            <label htmlFor="asientos-hasta">{t('ent.to')}<DateField id="asientos-hasta" value={dates.to} company={company} onChange={(d) => setDates((x) => ({ ...x, to: d }))} /></label>
          </div>)}
        <div className="rejilla-tres filtros-asientos">
          <label>{t('ent.col.state')}
            <select value={filters.state} onChange={(e) => setFilters({ ...filters, state: e.target.value })}>
              <option value="">{t('ent.allStates')}</option>
              {['posted', 'ok', 'error'].map((x) => <option key={x} value={x}>{t(`ent.state.${x}`)}</option>)}
            </select>
          </label>
          <label>{t('ent.col.source')}
            <select value={filters.source} onChange={(e) => setFilters({ ...filters, source: e.target.value })}>
              <option value="">{t('ent.allSources')}</option>
              {sources.map((x) => <option key={x} value={x}>{t(`ent.source.${x}`)}</option>)}
            </select>
          </label>
          <label>{t('ent.search')}
            <input type="search" value={filters.text} placeholder={t('ent.searchPlaceholder')} onChange={(e) => setFilters({ ...filters, text: e.target.value })} />
          </label>
        </div>
        <ErrorBox error={error} company={company} />
        {message && <p className="exito" role="status">✓ {message}</p>}
        {rows && (
          <p className="resumen-comprobaciones" role="status">
            {['posted', 'ok', 'error'].filter((x) => s[x]).map((x) => (
              <span key={x} className={`insignia-estado estado-${x}`}>{ICON[x]} {t(`ent.count.${x}`).replace('{n}', s[x])}</span>))}
          </p>)}
        {rows && <ReportActions onExcel={exportExcel} info={`${company.name ?? ''}`} />}
      </section>

      <section className="tarjeta">
        {!readOnly && sel.length > 0 && (
          <div className="fila-botones">
            <button type="button" disabled={busy} onClick={postSelected}>{t('ent.postSelected').replace('{n}', sel.length)}</button>
            <button type="button" className="secundario" onClick={() => setChecked([])}>{t('cancel')}</button>
          </div>)}
        {rows === null ? <p className="ayuda">{t('loadingData')}…</p> : list.length === 0 ? <p className="ayuda">{t('ent.empty')}</p> : (
          <div className="tabla-ancha" tabIndex={0} role="region" aria-label={t('nav.entries.label')}>
            <table className="informe lista-asientos">
              <thead><tr>
                {!readOnly && <th scope="col"><span className="oculto">{t('ent.select')}</span></th>}
                <th scope="col" className="num">{t('ent.col.no')}</th><th scope="col">{t('ent.col.date')}</th><th scope="col">{t('ent.col.doc')}</th>
                <th scope="col">{t('ent.col.concept')}</th><th scope="col" className="num">{t('ent.col.debit')}</th><th scope="col" className="num">{t('ent.col.credit')}</th>
                <th scope="col">{t('ent.col.source')}</th><th scope="col">{t('ent.col.state')}</th>
                {!readOnly && <th scope="col"><span className="oculto">{t('ent.actions')}</span></th>}
              </tr></thead>
              <tbody>{list.map((r) => (
                <tr key={r.entry_id} className={`fila-asiento estado-${r.state}`} onClick={() => navigate(to(rowTarget(r)))}>
                  {!readOnly && (
                    <td onClick={(e) => e.stopPropagation()}>
                      {selectable(r) && <input type="checkbox" aria-label={t('ent.selectOne').replace('{c}', r.description)} checked={checked.includes(r.entry_id)}
                        onChange={(e) => setChecked(e.target.checked ? [...checked, r.entry_id] : checked.filter((x) => x !== r.entry_id))} />}
                    </td>)}
                  <td className="num">{r.entry_no ?? '—'}</td>
                  <td>{showDate(r.posting_date)}</td>
                  <td>{r.document_no ?? ''}</td>
                  <td><Link to={to(rowTarget(r))} className="enlace-fila" onClick={(e) => e.stopPropagation()}>{r.description}</Link>
                    {r.reversed_by_no && <small className="ayuda"> · {t('ent.reversedBy').replace('{n}', r.reversed_by_no)}</small>}</td>
                  <td className="num">{money(r.total_debit, language)}</td>
                  <td className="num">{money(r.total_credit, language)}</td>
                  <td>{t(`ent.source.${r.source}`)}</td>
                  <td><span className={`texto-estado estado-${r.state}`}>{ICON[r.state]} {t(`ent.state.${r.state}`)}</span>
                    {r.problem && <small className="motivo">{t(`ent.problem.${r.problem}`)}</small>}</td>
                  {!readOnly && (
                    <td onClick={(e) => e.stopPropagation()}>
                      {r.status === 'draft' && (confirmDelete === r.entry_id
                        ? <span className="fila-botones"><button type="button" className="secundario peligro" onClick={() => remove(r.entry_id)}>{t('ent.confirmDelete')}</button>
                            <button type="button" className="enlace" onClick={() => setConfirmDelete(null)}>{t('cancel')}</button></span>
                        : <button type="button" className="papelera visible" aria-label={t('ent.delete').replace('{c}', r.description)} title={t('ent.delete').replace('{c}', r.description)}
                                  onClick={() => setConfirmDelete(r.entry_id)}><Trash2 size={16} aria-hidden="true" /></button>)}
                    </td>)}
                </tr>))}</tbody>
              <tfoot><tr className="total">
                {!readOnly && <td />}
                <td colSpan={4}>{t('ent.totals').replace('{n}', list.length)}</td>
                <td className="num">{money(s.debit, language)}</td><td className="num">{money(s.credit, language)}</td><td colSpan={readOnly ? 2 : 3} />
              </tr></tfoot>
            </table>
          </div>)}
        {rows && rows.length < total && (
          <button type="button" className="secundario" onClick={more}>{t('ent.more').replace('{n}', rows.length).replace('{t}', total)}</button>)}
      </section>
    </>
  )
}
