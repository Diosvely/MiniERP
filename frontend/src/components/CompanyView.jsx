import { useState } from 'react'
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

// Pantalla de una empresa con pestañas
//   readOnly   → empresa demo de otro usuario (o rol viewer): solo consultar
//   canPublish → el propietario de la app puede publicar/despublicar la empresa como demo
export default function CompanyView({ company, readOnly, canPublish, onChanged, onBack }) {
  const { t } = useI18n()
  const [tab, setTab] = useState(readOnly ? 'journal' : 'entry')
  const [refreshKey, setRefreshKey] = useState(0)
  const [error, setError] = useState('')

  const tabs = [
    ...(readOnly ? [] : [['entry', t('tabEntry')]]),
    ['invoices', t('tabInvoices')],
    ['journal', t('tabJournal')],
    ['reports', t('tabReports')],
    ['accounts', t('tabAccounts')],
    ['partners', t('tabPartners')],
    ['taxes', t('tabTaxes')],
    ['settlement', t('tabSettlement')],
  ]

  async function togglePublish() {
    setError('')
    const { error } = await supabase.from('companies')
      .update({ is_demo: !company.is_demo }).eq('id', company.id)
    if (error) return setError(error.message)
    onChanged({ ...company, is_demo: !company.is_demo })
  }

  return (
    <>
      <div className="empresa-cabecera">
        <button className="secundario" onClick={onBack}>← {t('back')}</button>
        <div>
          <strong>
            {company.name} {company.is_demo && <span className="insignia">{t('demoBadge')}</span>}
          </strong>
          <span>{t(`territory.${company.tax_territory}`)}</span>
        </div>
      </div>

      {readOnly && <p className="solo-lectura">👁 {t('readOnly')}</p>}

      {canPublish && (
        <p className="publicar">
          <button className="secundario" onClick={togglePublish}>
            {company.is_demo ? t('unpublishDemo') : t('publishDemo')}
          </button>
        </p>
      )}
      {error && <p className="aviso">⚠ {error}</p>}

      <nav className="pestanas">
        {tabs.map(([id, label]) => (
          <button key={id} className={tab === id ? 'activa' : ''} onClick={() => setTab(id)}>{label}</button>
        ))}
      </nav>

      {tab === 'entry' && !readOnly && <JournalEntryForm company={company} onPosted={() => setRefreshKey((k) => k + 1)} />}
      {tab === 'invoices' && <Invoices company={company} readOnly={readOnly} />}
      {tab === 'journal' && <GeneralJournal company={company} refreshKey={refreshKey} />}
      {tab === 'reports' && <Reports company={company} />}
      {tab === 'accounts' && <Accounts company={company} readOnly={readOnly} />}
      {tab === 'partners' && <Partners company={company} readOnly={readOnly} />}
      {tab === 'taxes' && <Taxes company={company} readOnly={readOnly} />}
        {tab === 'settlement' && <TaxSettlement company={company} readOnly={readOnly} />}
    </>
  )
}