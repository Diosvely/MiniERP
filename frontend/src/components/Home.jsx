import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { money } from '../format'
import { companyPath } from '../router'
import Link from './Link'
import Empty from './Empty'
import Loading from './Loading'
import ErrorBox from './ErrorBox'
import HomeKpis from './HomeKpis'
import { workDate } from '../workDate'
import { BookText, PenLine, Receipt, Scale, SearchCheck } from 'lucide-react'
import { ICON } from '../icons'

// INICIO de la empresa (como el Role Center de Business Central): qué hacer a continuación y qué ha pasado.
//   · Empresa propia → RUTA GUIADA de 6 pasos para llevar un trimestre (cada paso se marca solo al hacerlo)
//   · Empresa importada o de solo lectura (demo) → RECORRIDO DEL AUDITOR por los informes
//   · Siempre: accesos rápidos (si puedes escribir) y los 5 últimos asientos contabilizados
// INDICADORES (v0.30.0): 5 cifras a la fecha de trabajo y la tesorería mes a mes (erp.home_kpis). Dependen de quién entra:
//   · Empresa importada o demo (auditor) → indicadores arriba, y debajo el recorrido del auditor.
//   · Empresa propia que empieza → primero la ruta guiada; sin indicadores hasta tener lo básico (impuestos, tercero,
//     factura y asiento: los 4 primeros pasos), porque saldrían a cero y no dicen nada.
//   · Con lo básico hecho → los indicadores aparecen debajo de la ruta; con la ruta completa, suben arriba y la ruta
//     se queda plegada ("✓ Ruta completada · ver los pasos").
// Las comprobaciones son consultas ligeras a las vistas que ya existen (select id … limit 1): no hay funciones nuevas.

// [id del paso, pantalla a la que lleva, consulta que dice si está hecho]
const STEPS = [
  ['taxes', 'taxes', (c) => supabase.from('v_tax_setup').select('tax_code').eq('company_id', c).limit(1)],
  ['partners', 'partners', (c) => supabase.from('v_partners').select('id').eq('company_id', c).limit(1)],
  ['invoice', 'invoices', (c) => supabase.from('v_invoices').select('id').eq('company_id', c).limit(1)],
  ['journal', 'journal', (c) => supabase.from('journal_entries').select('id').eq('company_id', c).eq('status', 'posted').limit(1)],
  ['settlement', 'settlement', (c) => supabase.from('v_tax_settlements').select('id').eq('company_id', c).limit(1)],
  ['statements', 'balance', null],   // hecho cuando ya hay asientos contabilizados (paso 4): ya hay algo que ver
]

// Recorrido del auditor: el orden en que un revisor mira unas cuentas que no ha llevado él
const TOUR = [
  ['journal', 'journal'], ['balance', 'balance'], ['pyg', 'pyg'],
  ['cashflow', 'cashflow'], ['ratios', 'ratios'], ['reports', 'reports'],
]

export default function Home({ company, readOnly, mode, onAuditor }) {
  const { t, language } = useI18n()
  const [info, setInfo] = useState(null)      // { done: {…}, imported, year, latest: […] }
  const [error, setError] = useState('')
  const to = (section) => companyPath(company.id, section)
  const tax = company.tax_territory === 'canary_islands' ? 'IGIC' : 'IVA'
  const wd = workDate(company)   // fecha de trabajo: los indicadores se calculan a esta fecha

  useEffect(() => {
    let alive = true
    const id = company.id
    Promise.all([
      Promise.all(STEPS.map(([, , q]) => (q ? q(id) : Promise.resolve({ data: [] })))),
      supabase.from('v_import_batches').select('id, source').eq('company_id', id).limit(1),
      supabase.from('fiscal_years').select('year, status').eq('company_id', id).order('year', { ascending: false }),
      supabase.from('journal_entries').select('id, entry_no, posting_date, description')
        .eq('company_id', id).eq('status', 'posted')
        .order('posting_date', { ascending: false }).order('entry_no', { ascending: false }).limit(5),
      // Indicadores: si fallan (p. ej. falta la migración 0031), el Inicio se ve igual, solo que sin ellos
      supabase.rpc('home_kpis', { p_company: id, p_date: wd }),
    ]).then(async ([checks, imp, years, entries, kpis]) => {
      const failed = [...checks, imp, years, entries].find((r) => r.error)
      if (failed) throw failed.error
      // Importe de cada asiento = suma del Debe de sus líneas (una sola consulta para los 5)
      const ids = (entries.data ?? []).map((e) => e.id)
      const lines = ids.length
        ? await supabase.from('journal_lines').select('entry_id, debit').in('entry_id', ids)
        : { data: [] }
      const total = (eid) => (lines.data ?? []).filter((l) => l.entry_id === eid).reduce((s, l) => s + Number(l.debit), 0)
      const done = Object.fromEntries(STEPS.map(([key], i) => [key, (checks[i].data ?? []).length > 0]))
      done.statements = done.journal
      if (!alive) return
      setInfo({
        done,
        imported: imp.data?.[0] ?? null,
        year: (years.data ?? []).find((y) => y.status === 'open')?.year ?? years.data?.[0]?.year ?? null,
        latest: (entries.data ?? []).map((e) => ({ ...e, amount: total(e.id) })),
        kpis: kpis.error ? null : kpis.data,
      })
    }).catch((e) => alive && setError(e.message ?? String(e)))
    return () => { alive = false }
  }, [company.id, wd])

  if (error) return <ErrorBox error={error} company={company} />
  if (!info) return <Loading />

  const tour = readOnly || Boolean(info.imported)
  const next = STEPS.findIndex(([key]) => !info.done[key])
  const doneCount = STEPS.filter(([key]) => info.done[key]).length
  const pathComplete = doneCount === STEPS.length
  const basics = ['taxes', 'partners', 'invoice', 'journal'].every((k) => info.done[k])
  const showKpis = Boolean(info.kpis) && Number(info.kpis.entries) > 0 && (tour || basics)
  const kpisFirst = showKpis && (tour || pathComplete)
  const kpiBlock = showKpis && <HomeKpis company={company} kpis={info.kpis} />
  const date = (d) => new Date(`${d}T00:00:00`).toLocaleDateString(language === 'en' ? 'en-GB' : 'es-ES')

  return (
    <div className="inicio">
      <div className="inicio-cabecera">
        <section className="tarjeta saludo">
          <h2>{t('homeHello').replace('{c}', company.name)}</h2>
          <p className="ayuda">
            {t(`territory.${company.tax_territory}`)} · {tax}
            {info.year && <> · {t('homeYear').replace('{y}', info.year)}</>}
            {company.work_date && <> · 📅 {t('homeWorkDate').replace('{d}', date(company.work_date))}</>}
            {info.imported && <> · 📥 {t('homeImportedFrom').replace('{s}', t(`importSource.${info.imported.source}`))}</>}
          </p>
        </section>
        {kpisFirst && kpiBlock}
      </div>

      <div className="inicio-principal">
        {tour ? (
          <section className="tarjeta ruta-guiada">
            <h2><SearchCheck {...ICON} /> {t(info.imported ? 'homeTourImported' : 'homeTourDemo')}</h2>
            <p className="ayuda">{t('homeTourIntro')}</p>
            {mode === 'basic' && (
              <p className="aviso-modo">
                🔍 {t('homeTourMode')}
                <button type="button" className="enlace" onClick={onAuditor}>{t('modeSwitchAuditor')}</button>
              </p>
            )}
            <ol className="pasos">
              {TOUR.map(([key, section], i) => (
                <li key={key} className="paso pendiente">
                  <span className="paso-numero" aria-hidden="true">{i + 1}</span>
                  <div className="paso-texto">
                    <strong>{t(`homeTour.${key}.title`)}</strong>
                    <span>{t(`homeTour.${key}.help`)}</span>
                  </div>
                  <Link to={to(section)} className="boton secundario">{t('homeOpen')}</Link>
                </li>
              ))}
            </ol>
          </section>
        ) : pathComplete ? (
          // Ruta terminada: se queda plegada debajo de los indicadores, por si se quiere repasar
          <details className="tarjeta ruta-plegada">
            <summary>✓ {t('homePathDone')}</summary>
            <ol className="pasos">
              {STEPS.map(([key, section]) => (
                <li key={key} className="paso hecho">
                  <span className="paso-numero" aria-hidden="true">✓</span>
                  <div className="paso-texto"><strong>{t(`homeStep.${key}.title`).replace('{tax}', tax)}</strong></div>
                  <Link to={to(section)} className="boton secundario">{t('homeOpen')}</Link>
                </li>
              ))}
            </ol>
          </details>
        ) : (
          <section className="tarjeta ruta-guiada">
            <div className="ruta-cabecera">
              <h2>{t('homePathTitle')}</h2>
              <span className="progreso-texto">{t('homeProgress').replace('{n}', doneCount).replace('{m}', STEPS.length)}</span>
            </div>
            <div className="progreso" role="progressbar" aria-label={t('homePathTitle')}
                 aria-valuemin={0} aria-valuemax={STEPS.length} aria-valuenow={doneCount}>
              <span style={{ width: `${(doneCount / STEPS.length) * 100}%` }} />
            </div>
            <p className="ayuda">{t('homePathIntro').replace('{tax}', tax)}</p>
            <ol className="pasos">
              {STEPS.map(([key, section], i) => {
                const state = info.done[key] ? 'hecho' : i === next ? 'siguiente' : 'pendiente'
                return (
                  <li key={key} className={`paso ${state}`} aria-current={state === 'siguiente' ? 'step' : undefined}>
                    <span className="paso-numero" aria-hidden="true">{state === 'hecho' ? '✓' : i + 1}</span>
                    <div className="paso-texto">
                      <strong>{t(`homeStep.${key}.title`).replace('{tax}', tax)}</strong>
                      <span>{state === 'hecho' ? t('homeStepDone') : t(`homeStep.${key}.help`).replace('{tax}', tax)}</span>
                    </div>
                    <Link to={to(section)} className={state === 'siguiente' ? 'boton' : 'boton secundario'}>
                      {state === 'hecho' ? t('homeOpen') : t(`homeStep.${key}.action`)}
                    </Link>
                  </li>
                )
              })}
            </ol>
          </section>
        )}

        {showKpis && !kpisFirst && kpiBlock}
      </div>

      <div className="inicio-lateral">
        {!readOnly && (
          <section className="tarjeta accesos-rapidos">
            <h2>{t('homeQuick')}</h2>
            <Link to={to('invoices')} className="acceso"><Receipt {...ICON} /> {t('homeQuickInvoice')}</Link>
            <Link to={to('entry')} className="acceso"><PenLine {...ICON} /> {t('homeQuickEntry')}</Link>
            <Link to={to('balance')} className="acceso"><Scale {...ICON} /> {t('homeQuickBalance')}</Link>
          </section>
        )}

        <section className="tarjeta ultimos">
          <h2>{t('homeLatest')}</h2>
          {info.latest.length === 0 ? (
            <Empty icon={BookText} text={t('homeLatestNone')}
                   action={readOnly ? null : t('homeQuickEntry')} to={readOnly ? null : to('entry')} />
          ) : (
            <>
              <ul>
                {info.latest.map((e) => (
                  <li key={e.id}>
                    <span className="ultimo-fecha">{date(e.posting_date)} · nº {e.entry_no}</span>
                    <span className="ultimo-concepto">{e.description}</span>
                    <strong className="num">{money(e.amount, language)} €</strong>
                  </li>
                ))}
              </ul>
              <Link to={to('journal')} className="enlace">{t('homeSeeJournal')} →</Link>
            </>
          )}
        </section>
      </div>
    </div>
  )
}
