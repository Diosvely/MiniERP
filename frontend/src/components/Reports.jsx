import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { fetchAll } from '../paging'
import { useI18n } from '../i18n'
import { workYear } from '../workDate'
import { accountName, money, shortDate } from '../format'
import Empty from './Empty'
import { companyPath, navigate } from '../router'
import ErrorBox from './ErrorBox'
import ReportActions from './ReportActions'
import { downloadXlsx, fileName } from '../exportXlsx'
import Link from './Link'

const LEVELS = [['', 'levelPosting'], ['3', 'levelAccount'], ['2', 'levelSubgroup'], ['1', 'levelGroup']]

// Informes del auditor: sumas y saldos, libro mayor y saldos anómalos
// params (desde la ruta): ['mayor', cuenta, año] abre directamente el libro mayor de esa cuenta (rastro contable)
export default function Reports({ company, params = [] }) {
  const { t, language } = useI18n()
  const fromLink = params[0] === 'mayor' && params[1]
  const [view, setView] = useState(fromLink ? 'ledger' : 'trial')
  const [years, setYears] = useState([])
  const [year, setYear] = useState(() => (fromLink && Number(params[2])) || workYear(company))   // año de la fecha de trabajo
  const [level, setLevel] = useState('')
  const [toDate, setToDate] = useState('')
  const [trial, setTrial] = useState([])
  const [anomalies, setAnomalies] = useState([])
  const [accounts, setAccounts] = useState([])
  const [ledgerAccount, setLedgerAccount] = useState(fromLink ? params[1] : '')
  const [ledger, setLedger] = useState([])
  const [error, setError] = useState('')

  const m = (v) => money(v, language)
  const name = (r) => (language === 'en' ? r.name_en || r.name : r.name)
  // Saldo con su lado: 1.234,00 D (deudor) · 1.234,00 H (acreedor)
  const side = (v) => (Number(v) === 0 ? m(0) : `${m(Math.abs(v))} ${Number(v) > 0 ? t('debitShort') : t('creditShort')}`)

  useEffect(() => {
    Promise.all([
      supabase.from('fiscal_years').select('year').eq('company_id', company.id).order('year'),
      fetchAll(() => supabase.from('gl_accounts').select('account_no, name, name_en')
        .eq('company_id', company.id).eq('account_type', 'posting').order('account_no')),
    ]).then(([y, a]) => {
      if (y.error || a.error) return setError((y.error || a.error).message)
      setYears(y.data.map((r) => r.year))
      if (y.data.length && !y.data.some((r) => r.year === Number(year))) setYear(y.data[y.data.length - 1].year)
      setAccounts(a.data)
    })
  }, [company.id])

  // Sumas y saldos + anomalías del mismo nivel y fecha
  useEffect(() => {
    const args = { p_company: company.id, p_year: Number(year), p_level: level ? Number(level) : null, p_to_date: toDate || null }
    Promise.all([fetchAll(() => supabase.rpc('trial_balance', args)), supabase.rpc('balance_anomalies', args)])
      .then(([tb, an]) => {
        if (tb.error || an.error) return setError((tb.error || an.error).message)
        setError(''); setTrial(tb.data); setAnomalies(an.data)
      })
  }, [company.id, year, level, toDate])

  // Libro mayor de una subcuenta: la función filtra primero y calcula el saldo después (0029),
  // y se lee por páginas porque una cuenta puede tener más de 1.000 apuntes en un año
  useEffect(() => {
    if (!ledgerAccount) return setLedger([])
    let alive = true
    fetchAll(() => supabase.rpc('general_ledger', {
      p_company: company.id, p_year: Number(year), p_account: ledgerAccount, p_to_date: toDate || null,
    })).then(({ data, error }) => {
      if (!alive) return
      if (error) return setError(error.message)
      setError(''); setLedger(data)
    })
    return () => { alive = false }
  }, [company.id, year, ledgerAccount, toDate])

  // La dirección sigue al mayor que se está viendo: al volver desde un asiento («atrás») se abre esta misma cuenta
  useEffect(() => {
    if (view === 'ledger' && ledgerAccount) {
      navigate(companyPath(company.id, `reports/mayor/${ledgerAccount}/${year}`), { replace: true })
    } else {
      navigate(companyPath(company.id, 'reports'), { replace: true })
    }
  }, [view, ledgerAccount, year, company.id])

  const anomalyOf = (no) => anomalies.find((a) => a.account_no === no)
  const sum = (field) => trial.reduce((s, r) => s + Number(r[field]), 0)
  const totals = { d: sum('total_debit'), c: sum('total_credit'), sd: sum('debit_balance'), sc: sum('credit_balance') }
  const balanced = Math.round(totals.d * 100) === Math.round(totals.c * 100)

  function openLedger(no) {
    if (no.length !== company.posting_account_digits) return
    setLedgerAccount(no); setView('ledger')
  }

  const ledgerDebit = ledger.reduce((s, r) => s + Number(r.debit), 0)
  const ledgerCredit = ledger.reduce((s, r) => s + Number(r.credit), 0)
  const accountInfo = accounts.find((a) => a.account_no === ledgerAccount)

  return (
    <>
      <nav className="pestanas">
        {[['trial', t('trialBalance')], ['ledger', t('generalLedger')], ['anomalies', `${t('anomalies')} (${anomalies.length})`]].map(([id, label]) => (
          <button key={id} type="button" className={view === id ? 'activa' : ''} onClick={() => setView(id)}>{label}</button>
        ))}
      </nav>

      <section className="tarjeta">
        <div className="rejilla-tres">
          <label>{t('year')}
            <select value={year} onChange={(e) => setYear(e.target.value)}>
              {years.map((y) => <option key={y} value={y}>{y}</option>)}
            </select>
          </label>
          {view === 'trial' ? (
            <label>{t('level')}
              <select value={level} onChange={(e) => setLevel(e.target.value)}>
                {LEVELS.map(([v, k]) => <option key={k} value={v}>{t(k)}</option>)}
              </select>
            </label>
          ) : view === 'ledger' ? (
            <label>{t('account')}
              <select value={ledgerAccount} onChange={(e) => setLedgerAccount(e.target.value)}>
                <option value="">—</option>
                {accounts.map((a) => <option key={a.account_no} value={a.account_no}>{a.account_no} · {accountName(a, language)}</option>)}
              </select>
            </label>
          ) : <span />}
          <label>{t('toDate')}
            <input type="date" value={toDate} onChange={(e) => setToDate(e.target.value)} />
          </label>
        </div>
        <ErrorBox error={error} company={company} />
      </section>

      {view === 'trial' && (
        <section className="tarjeta">
          <div className="titulo-informe">
            <h2>{t('trialBalance')} {year}</h2>
            {trial.length > 0 && <ReportActions info={`${company.name} · ${t('year')} ${year}${toDate ? ` · ${t('toDate')} ${toDate}` : ''}`}
              onExcel={() => downloadXlsx({
                title: `${t('trialBalance')} · ${company.name}`, sheet: t('trialBalance'),
                subtitle: `${t('year')} ${year}${toDate ? ` · ${t('toDate')} ${toDate}` : ''}`,
                file: fileName(t('trialBalance'), company.name, year, toDate),
                columns: [
                  { header: t('account'), key: 'no', type: 'text', width: 12 },
                  { header: t('accountName'), key: 'name', type: 'text', width: 44 },
                  { header: t('debit'), key: 'd', type: 'money' }, { header: t('credit'), key: 'c', type: 'money' },
                  { header: t('debitBalance'), key: 'sd', type: 'money' }, { header: t('creditBalance'), key: 'sc', type: 'money' },
                ],
                rows: trial.map((r) => ({ no: r.account_no, name: name(r) ?? '', d: r.total_debit, c: r.total_credit,
                  sd: Number(r.debit_balance) || null, sc: Number(r.credit_balance) || null })),
              })} />}
          </div>
          <p className="ayuda">{t('trialBalanceHelp')}</p>
          <div className="tabla-scroll">
            <table className="informe tarjetas-movil">
              <thead>
                <tr>
                  <th>{t('account')}</th>
                  <th className="num">{t('debit')}</th><th className="num">{t('credit')}</th>
                  <th className="num">{t('debitBalance')}</th><th className="num">{t('creditBalance')}</th>
                </tr>
              </thead>
              <tbody>
                {trial.map((r) => {
                  const a = anomalyOf(r.account_no)
                  return (
                    <tr key={r.account_no} className={a ? `anomalia ${a.severity}` : ''}
                        onClick={() => openLedger(r.account_no)}
                        title={a ? (language === 'en' ? a.note_en : a.note) ?? '' : ''}>
                      <td className="celda-titulo"><span className="codigo">{r.account_no}</span> {name(r) ?? ''} {a && '⚠'}</td>
                      <td className="num" data-label={t('debit')}>{m(r.total_debit)}</td>
                      <td className="num" data-label={t('credit')}>{m(r.total_credit)}</td>
                      <td className="num" data-label={t('debitBalance')}>{Number(r.debit_balance) ? m(r.debit_balance) : ''}</td>
                      <td className="num" data-label={t('creditBalance')}>{Number(r.credit_balance) ? m(r.credit_balance) : ''}</td>
                    </tr>
                  )
                })}
                <tr className="total">
                  <td className="celda-titulo">{t('total')} {balanced ? '✓' : '⚠'}</td>
                  <td className="num" data-label={t('debit')}>{m(totals.d)}</td>
                  <td className="num" data-label={t('credit')}>{m(totals.c)}</td>
                  <td className="num" data-label={t('debitBalance')}>{m(totals.sd)}</td>
                  <td className="num" data-label={t('creditBalance')}>{m(totals.sc)}</td>
                </tr>
              </tbody>
            </table>
          </div>
          {trial.length === 0 && (
            <Empty icon="📒" text={t('noEntries')} action={company.my_role && company.my_role !== 'viewer' ? t('actionNewEntry') : null}
                   to={companyPath(company.id, 'entry')} />
          )}
        </section>
      )}

      {view === 'ledger' && (
        <section className="tarjeta">
          <div className="titulo-informe">
            <h2>{t('generalLedger')} {ledgerAccount && `· ${ledgerAccount} ${accountInfo ? accountName(accountInfo, language) : ''}`}</h2>
            {ledger.length > 0 && <ReportActions info={`${company.name} · ${t('year')} ${year}${toDate ? ` · ${t('toDate')} ${toDate}` : ''}`}
              onExcel={() => downloadXlsx({
                title: `${t('generalLedger')} ${ledgerAccount} ${accountInfo ? accountName(accountInfo, language) : ''} · ${company.name}`,
                subtitle: `${t('year')} ${year}${toDate ? ` · ${t('toDate')} ${toDate}` : ''}`, sheet: ledgerAccount,
                file: fileName(t('generalLedger'), ledgerAccount, company.name, year),
                columns: [
                  { header: t('date'), key: 'date', type: 'date', width: 12 }, { header: t('entry'), key: 'no', type: 'int', width: 9 },
                  { header: t('description'), key: 'desc', type: 'text', width: 50 },
                  { header: t('debit'), key: 'd', type: 'money' }, { header: t('credit'), key: 'c', type: 'money' },
                  { header: t('balance'), key: 'bal', type: 'money' },
                ],
                rows: ledger.map((r) => ({ date: r.posting_date, no: r.entry_no, desc: r.description,
                  d: Number(r.debit) || null, c: Number(r.credit) || null, bal: r.running_balance })),
              })} />}
          </div>
          {!ledgerAccount && <p className="ayuda">{t('chooseAccount')}</p>}
          {ledgerAccount && (
            <div className="tabla-scroll">
              <table className="informe tarjetas-movil">
                <thead>
                  <tr>
                    <th>{t('date')}</th><th>{t('entry')}</th><th>{t('description')}</th>
                    <th className="num">{t('debit')}</th><th className="num">{t('credit')}</th><th className="num">{t('balance')}</th>
                  </tr>
                </thead>
                <tbody>
                  {ledger.map((r, i) => (
                    <tr key={i}>
                      <td className="celda-fecha">{shortDate(r.posting_date)}</td>
                      <td className="celda-asiento"><Link to={companyPath(company.id, `asiento/${year}/${r.entry_no}`)} className="num-asiento"
                                title={t('openEntry')}>{r.entry_no}</Link></td>
                      <td className="celda-titulo">{r.description}</td>
                      <td className="num" data-label={t('debit')}>{Number(r.debit) ? m(r.debit) : ''}</td>
                      <td className="num" data-label={t('credit')}>{Number(r.credit) ? m(r.credit) : ''}</td>
                      <td className="num" data-label={t('balance')}>{side(r.running_balance)}</td>
                    </tr>
                  ))}
                  <tr className="total">
                    <td colSpan={3} className="celda-titulo">{t('total')}</td>
                    <td className="num" data-label={t('debit')}>{m(ledgerDebit)}</td>
                    <td className="num" data-label={t('credit')}>{m(ledgerCredit)}</td>
                    <td className="num" data-label={t('balance')}>{side(ledgerDebit - ledgerCredit)}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          )}
          {ledgerAccount && ledger.length === 0 && <p>{t('noMovements')}</p>}
        </section>
      )}

      {view === 'anomalies' && (
        <section className="tarjeta">
          <h2>{t('anomalies')}</h2>
          <p className="ayuda">{t('anomaliesHelp')}</p>
          {anomalies.length === 0 && <p className="exito">✓ {t('noAnomalies')}</p>}
          <ul className="anomalias">
            {anomalies.map((a) => (
              <li key={a.account_no} className={a.severity}>
                <strong>
                  <span className="codigo">{a.account_no}</span> {name(a)}
                  <span className={`insignia ${a.severity}`}>{t(`severity.${a.severity}`)}</span>
                </strong>
                <span>
                  {t('expectedBalance')}: {t(`nature.${a.expected}`)} · {t('actualBalance')}: <strong>{side(a.balance)}</strong>
                </span>
                {(language === 'en' ? a.note_en : a.note) && <span className="ayuda">{language === 'en' ? a.note_en : a.note}</span>}
                {a.reclass_to && <span>↪ {t('reclassTo')} <strong>{a.reclass_to}</strong></span>}
                {a.account_no.length === company.posting_account_digits && (
                  <button type="button" className="secundario" onClick={() => openLedger(a.account_no)}>{t('seeLedger')}</button>
                )}
              </li>
            ))}
          </ul>
        </section>
      )}
    </>
  )
}
