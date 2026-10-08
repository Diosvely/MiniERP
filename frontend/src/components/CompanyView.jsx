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

// Última pantalla abierta en cada empresa (comodidad; si el navegador no deja guardar, no pasa nada)
const remembered = (id) => { try { return localStorage.getItem(`erp-seccion-${id}`) } catch { return null } }
const remember = (id, s) => { try { localStorage.setItem(`erp-seccion-${id}`, s) } catch { /* sin almacenamiento */ } }

//   readOnly   → empresa demo de otro usuario (o rol viewer): solo consultar
//   canPublish → el propietario de la app puede publicar/despublicar la empresa como demo
export default function CompanyView({ company, readOnly, canPublish, onChanged, onBack }) {
  const { t } = useI18n()
  const menu = MENU.map(([group, items]) => [group, items.filter(([, , write]) => !(write && readOnly))])
    .filter(([, items]) => items.length)
  const allowed = menu.flatMap(([, items]) => items.map(([id]) => id))
  const initial = () => {
    const saved = remembered(company.id)
    return allowed.includes(saved) ? saved : allowed[0]
  }
  const [section, setSection] = useState(initial)
  const [menuOpen, setMenuOpen] = useState(false)
  const [refreshKey, setRefreshKey] = useState(0)
  const [error, setError] = useState('')

  useEffect(() => { setSection(initial()) }, [company.id, readOnly])

  function go(id) {
    setSection(id); remember(company.id, id); setMenuOpen(false)
    window.scrollTo?.({ top: 0 })
  }

  async function togglePublish() {
    setError('')
    const { error } = await supabase.from('companies')
      .update({ is_demo: !company.is_demo }).eq('id', company.id)
    if (error) return setError(error.message)
    onChanged({ ...company, is_demo: !company.is_demo })
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
            <button type="button" className="secundario" onClick={togglePublish}>
              {company.is_demo ? t('unpublishDemo') : t('publishDemo')}
            </button>
          </div>
        )}
      </aside>

      <section className="empresa-contenido">
        {readOnly && <p className="solo-lectura">👁 {t('readOnly')}</p>}
        {error && <p className="aviso">⚠ {error}</p>}
        <p className="ruta">{t(currentGroup)} › {t(currentItem)}</p>

        {section === 'entry' && !readOnly && <JournalEntryForm company={company} onPosted={() => setRefreshKey((k) => k + 1)} />}
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
      </section>
    </div>
  )
}
