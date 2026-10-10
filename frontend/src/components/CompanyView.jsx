import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import Accounts from './Accounts'
import JournalEntryForm from './JournalEntryForm'
import GeneralJournal from './GeneralJournal'
import Partners from './Partners'
import Taxes from './Taxes'
import Invoices from './Invoices'
import TaxSettlement from './TaxSettlement'
import Reports from './Reports'
import FinancialStatements from './FinancialStatements'
import YearClosing from './YearClosing'
import Withholdings from './Withholdings'
import ProRata from './ProRata'
import CashFlow from './CashFlow'
import Ratios from './Ratios'
import EntryTutor from './EntryTutor'
import CompanyAccess from './CompanyAccess'
import { companyPath, navigate, useHashRoute } from '../router'

// Menú agrupado por áreas, como el Role Center de Business Central o el menú de A3 / Sage:
//   Contabilidad · Facturas · Impuestos · Informes · Datos maestros
// En el ordenador es una barra lateral fija; en el móvil, un menú desplegable.
const MENU = [
  ['menuAccounting', [['entry', 'tabEntry', true], ['journal', 'tabJournal'], ['closing', 'menuYearClosing']]],
  ['menuInvoices', [['invoices', 'tabInvoices']]],
  ['menuTaxes', [['settlement', 'tabSettlement'], ['withholdings', 'menuWithholdings'], ['prorata', 'menuProRata'], ['taxes', 'menuTaxSetup']]],
  ['menuReports', [['balance', 'menuBalance'], ['pyg', 'menuPyg'], ['cashflow', 'menuCashFlow'], ['ratios', 'menuRatios'], ['reports', 'menuReportsItem']]],
  ['menuMasterData', [['accounts', 'menuChart'], ['partners', 'tabPartners']]],
]

// Última pantalla abierta en cada empresa: respaldo cuando la dirección no trae pantalla (#/empresa/<id>)
const remembered = (id) => { try { return localStorage.getItem(`erp-seccion-${id}`) } catch { return null } }
const remember = (id, s) => { try { localStorage.setItem(`erp-seccion-${id}`, s) } catch { /* sin almacenamiento */ } }

//   readOnly   → empresa demo de otro usuario (o rol viewer): solo consultar
//   canPublish → el propietario de la app o el titular de los datos (Miembro) publican/despublican la demo
//   isOwner    → el propietario de la app: ve el apartado Accesos (quién entra y con qué rol)
export default function CompanyView({ company, readOnly, canPublish, isOwner, onChanged, onBack }) {
  const { t } = useI18n()
  const menu = MENU.map(([group, items]) => [group, [
    ...items.filter(([, , write]) => !(write && readOnly)),
    ...(group === 'menuMasterData' && isOwner && company.my_role === 'admin' ? [['access', 'menuAccess']] : []),
  ]]).filter(([, items]) => items.length)
  const allowed = menu.flatMap(([, items]) => items.map(([id]) => id))
  // La pantalla sale de la dirección (#/empresa/<id>/<pantalla>): el botón atrás, recargar y compartir el enlace funcionan.
  // Si no viene o no está permitida (p. ej. "entry" en una demo), la última abierta o la primera del menú.
  const route = useHashRoute()
  const fromRoute = route[0] === 'empresa' && route[1] === company.id ? route[2] : null
  const saved = remembered(company.id)
  const section = allowed.includes(fromRoute) ? fromRoute : allowed.includes(saved) ? saved : allowed[0]
  useEffect(() => {
    if (fromRoute !== section) navigate(companyPath(company.id, section), { replace: true })
    remember(company.id, section)
  }, [fromRoute, section, company.id])

  const [menuOpen, setMenuOpen] = useState(false)
  const [refreshKey, setRefreshKey] = useState(0)
  const [error, setError] = useState('')
  const [draft, setDraft] = useState(null)   // asiento propuesto por el Tutor de asientos

  function go(id) {
    setMenuOpen(false)
    navigate(companyPath(company.id, id))
    window.scrollTo?.({ top: 0 })
  }

  // Publicar como demo: se pide la mención y que acepte que los datos serán públicos. Despublicar es directo.
  const [publishing, setPublishing] = useState(null)   // { credit, accepted } mientras se rellena
  async function setDemo(demo, credit) {
    setError('')
    const { error } = await supabase.rpc('set_company_demo', { p_company: company.id, p_demo: demo, p_credit: credit ?? null })
    if (error) return setError(error.message)
    setPublishing(null)
    onChanged({ ...company, is_demo: demo, data_credit: credit?.trim() || company.data_credit })
  }

  const [currentGroup, currentItem] = (() => {
    for (const [group, items] of menu) {
      const item = items.find(([id]) => id === section)
      if (item) return [group, item[1]]
    }
    return ['', '']
  })()

  return (
    <div className="empresa-layout">
      <div className="empresa-cabecera">
        <button className="secundario" onClick={onBack}>← {t('back')}</button>
        <div>
          <strong>
            {company.name} {company.is_demo && <span className="insignia">{t('demoBadge')}</span>}
          </strong>
          <span>{t(`territory.${company.tax_territory}`)}</span>
          {company.data_credit && <span className="mencion">📊 {company.data_credit}</span>}
        </div>
      </div>

      {/* Móvil: botón de menú con la ruta actual (Área › Pantalla) */}
      <button type="button" className="boton-menu" aria-expanded={menuOpen} onClick={() => setMenuOpen(!menuOpen)}>
        <span>☰</span> {t(currentGroup)} › <strong>{t(currentItem)}</strong>
      </button>

      <aside className={menuOpen ? 'menu-empresa abierto' : 'menu-empresa'}>
        {menu.map(([group, items]) => (
          <div key={group} className="menu-grupo">
            <h3>{t(group)}</h3>
            {items.map(([id, label]) => (
              <button key={id} type="button" className={section === id ? 'activa' : ''} onClick={() => go(id)}>
                {t(label)}
              </button>
            ))}
          </div>
        ))}
        {canPublish && (
          <div className="menu-grupo">
            <button type="button" className="secundario"
                    onClick={() => (company.is_demo ? setDemo(false) : setPublishing({ credit: company.data_credit ?? '', accepted: false }))}>
              {company.is_demo ? t('unpublishDemo') : t('publishDemo')}
            </button>
          </div>
        )}
      </aside>

      <section className="empresa-contenido">
        {readOnly && <p className="solo-lectura">👁 {t('readOnly')}</p>}
        {error && <p className="aviso">⚠ {error}</p>}
        {company.is_data_owner && <p className="titular">🤝 {t('dataOwnerBanner')}</p>}
        {publishing && (
          <section className="tarjeta publicar-demo">
            <h2>{t('publishTitle')}</h2>
            <p className="ayuda">{t('publishIntro')}</p>
            <label>{t('publishCredit')}
              <input maxLength={200} value={publishing.credit} placeholder={t('publishCreditPlaceholder')}
                     onChange={(e) => setPublishing({ ...publishing, credit: e.target.value })} />
            </label>
            <label className="opcion">
              <input type="checkbox" checked={publishing.accepted}
                     onChange={(e) => setPublishing({ ...publishing, accepted: e.target.checked })} />
              {t('publishAccept')}
            </label>
            <div className="fila">
              <button type="button" className="secundario" onClick={() => setPublishing(null)}>{t('cancel')}</button>
              <button type="button" disabled={!publishing.accepted} onClick={() => setDemo(true, publishing.credit)}>{t('publishDemo')}</button>
            </div>
          </section>
        )}
        <p className="ruta">{t(currentGroup)} › {t(currentItem)}</p>

        {section === 'entry' && !readOnly && <EntryTutor company={company} onLoad={setDraft} />}
        {section === 'entry' && !readOnly && (
          <JournalEntryForm company={company} draft={draft} onPosted={() => setRefreshKey((k) => k + 1)} />
        )}
        {section === 'journal' && <GeneralJournal company={company} readOnly={readOnly} refreshKey={refreshKey} />}
        {section === 'closing' && <YearClosing company={company} readOnly={readOnly} />}
        {section === 'invoices' && <Invoices company={company} readOnly={readOnly} />}
        {section === 'settlement' && <TaxSettlement company={company} readOnly={readOnly} />}
        {section === 'prorata' && <ProRata company={company} readOnly={readOnly} />}
        {section === 'withholdings' && <Withholdings company={company} />}
        {section === 'taxes' && <Taxes company={company} readOnly={readOnly} onChanged={onChanged} />}
        {section === 'balance' && <FinancialStatements company={company} statement="balance" />}
        {section === 'pyg' && <FinancialStatements company={company} statement="pyg" />}
        {section === 'cashflow' && <CashFlow company={company} />}
        {section === 'ratios' && <Ratios company={company} />}
        {section === 'reports' && <Reports company={company} />}
        {section === 'accounts' && <Accounts company={company} readOnly={readOnly} />}
        {section === 'partners' && <Partners company={company} readOnly={readOnly} />}
        {section === 'access' && isOwner && <CompanyAccess company={company} />}
      </section>
    </div>
  )
}
