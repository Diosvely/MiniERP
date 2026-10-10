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
import Home from './Home'
import Term from './Term'
import { SECTION_TERM } from '../glossary'
import { companyPath, navigate, useHashRoute } from '../router'
import ErrorBox from './ErrorBox'

// PANTALLAS de la empresa. Dos menús sobre las mismas pantallas (como los "perfiles" de Business Central):
//   · Modo BÁSICO (por defecto): lista corta, solo lo del día a día, en lenguaje sencillo.
//   · Modo AUDITOR: todo, agrupado por áreas como en A3 / Sage: Contabilidad · Facturas · Impuestos · Informes · Datos maestros.
// Cada entrada lleva un nombre sencillo y, debajo, el término técnico (nav.<id>.label / nav.<id>.sub en el i18n).
//   basic: true      → sale en el menú Básico
//   basic: 'hidden'  → no sale en el menú Básico, pero es del modo Básico (se llega desde Inicio; sin aviso)
//   write: true      → solo si se puede escribir (no en demos ni para el rol viewer)
const SCREENS = [
  { id: 'home', group: '', basic: true },
  { id: 'entry', group: 'menuAccounting', basic: true, write: true },
  { id: 'journal', group: 'menuAccounting', basic: true },
  { id: 'closing', group: 'menuAccounting' },
  { id: 'invoices', group: 'menuInvoices', basic: true },
  { id: 'settlement', group: 'menuTaxes', basic: true },
  { id: 'withholdings', group: 'menuTaxes' },
  { id: 'prorata', group: 'menuTaxes' },
  { id: 'taxes', group: 'menuTaxes', basic: 'hidden' },
  { id: 'balance', group: 'menuReports', basic: true },
  { id: 'pyg', group: 'menuReports', basic: true },
  { id: 'cashflow', group: 'menuReports' },
  { id: 'ratios', group: 'menuReports' },
  { id: 'reports', group: 'menuReports' },
  { id: 'accounts', group: 'menuMasterData' },
  { id: 'partners', group: 'menuMasterData', basic: true },
  { id: 'access', group: 'menuMasterData', owner: true },
]
// Orden del menú Básico (8 entradas como máximo): de lo que más se usa a lo que menos
const BASIC_ORDER = ['home', 'invoices', 'entry', 'journal', 'settlement', 'balance', 'pyg', 'partners']

// Modo elegido: se guarda en este navegador (si no deja guardar, siempre empieza en Básico)
const savedMode = () => { try { return localStorage.getItem('erp-modo') === 'auditor' ? 'auditor' : 'basic' } catch { return 'basic' } }
const saveMode = (m) => { try { localStorage.setItem('erp-modo', m) } catch { /* sin almacenamiento */ } }

//   readOnly   → empresa demo de otro usuario (o rol viewer): solo consultar
//   canPublish → el propietario de la app o el titular de los datos (Miembro) publican/despublican la demo
//   isOwner    → el propietario de la app: ve el apartado Accesos (quién entra y con qué rol)
export default function CompanyView({ company, readOnly, canPublish, isOwner, onChanged, onBack }) {
  const { t } = useI18n()
  const [mode, setModeState] = useState(savedMode)
  const setMode = (m) => { setModeState(m); saveMode(m) }

  // Pantallas a las que tiene acceso (en los dos modos): el modo solo cambia el menú, no los permisos
  const screens = SCREENS.filter((s) => !(s.write && readOnly) && !(s.owner && !(isOwner && company.my_role === 'admin')))
  const allowed = screens.map((s) => s.id)
  const byId = Object.fromEntries(screens.map((s) => [s.id, s]))
  const menu = mode === 'basic'
    ? [['', BASIC_ORDER.filter((id) => byId[id])]]
    : [...new Set(screens.map((s) => s.group))].map((g) => [g, screens.filter((s) => s.group === g).map((s) => s.id)])

  // Textos del menú: el de la liquidación dice IVA (303) o IGIC (420) según el territorio
  const tax = company.tax_territory === 'canary_islands' ? { tax: 'IGIC', form: '420' } : { tax: 'IVA', form: '303' }
  const label = (id) => t(`nav.${id}.label`).replace('{tax}', tax.tax).replace('{form}', tax.form)
  const sub = (id) => t(`nav.${id}.sub`).replace('{tax}', tax.tax).replace('{form}', tax.form)

  // La pantalla sale de la dirección (#/empresa/<id>/<pantalla>): el botón atrás, recargar y compartir el enlace funcionan.
  // Si no viene o no está permitida (p. ej. "entry" en una demo), se abre el Inicio.
  const route = useHashRoute()
  const fromRoute = route[0] === 'empresa' && route[1] === company.id ? route[2] : null
  const section = allowed.includes(fromRoute) ? fromRoute : 'home'
  useEffect(() => {
    if (fromRoute !== section) navigate(companyPath(company.id, section), { replace: true })
  }, [fromRoute, section, company.id])
  // Pantalla del modo Auditor abierta en modo Básico (por un enlace o desde el Inicio): se muestra con un aviso
  const advanced = mode === 'basic' && !byId[section]?.basic

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

  const group = mode === 'auditor' ? byId[section]?.group : ''

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
        <div className="modo" role="group" aria-label={t('modeLabel')}>
          {['basic', 'auditor'].map((m) => (
            <button key={m} type="button" className={mode === m ? 'activo' : ''} aria-pressed={mode === m}
                    title={t(`modeHelp.${m}`)} onClick={() => setMode(m)}>
              {t(`mode.${m}`)}
            </button>
          ))}
        </div>
      </div>

      {/* Móvil: botón de menú con la ruta actual (Área › Pantalla) */}
      <button type="button" className="boton-menu" aria-expanded={menuOpen} onClick={() => setMenuOpen(!menuOpen)}>
        <span>☰</span> {group && <>{t(group)} › </>}<strong>{label(section)}</strong>
      </button>

      <aside className={menuOpen ? 'menu-empresa abierto' : 'menu-empresa'}>
        {menu.map(([g, ids]) => (
          <div key={g || 'basico'} className="menu-grupo">
            {g && <h3>{t(g)}</h3>}
            {ids.map((id) => (
              <button key={id} type="button" className={section === id ? 'activa' : ''}
                      aria-current={section === id ? 'page' : undefined} onClick={() => go(id)}>
                {label(id)}
                {sub(id) && <small>{sub(id)}</small>}
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
        <ErrorBox error={error} company={company} />
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
        {section !== 'home' && (
          <p className="ruta">
            {group && <>{t(group)} › </>}
            {SECTION_TERM[section] ? <Term id={SECTION_TERM[section]}>{label(section)}</Term> : label(section)}
          </p>
        )}
        {advanced && (
          <p className="aviso-modo">
            🔍 {t('modeAdvancedScreen')}
            <button type="button" className="enlace" onClick={() => setMode('auditor')}>{t('modeSwitchAuditor')}</button>
          </p>
        )}

        {section === 'home' && <Home company={company} readOnly={readOnly} mode={mode} onAuditor={() => setMode('auditor')} />}
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
