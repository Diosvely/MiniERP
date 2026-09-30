import { useState } from 'react'
import { useI18n } from '../i18n'
import Accounts from './Accounts'
import JournalEntryForm from './JournalEntryForm'
import GeneralJournal from './GeneralJournal'

// Pantalla de una empresa con pestañas
export default function CompanyView({ company, onBack }) {
  const { t } = useI18n()
  const [tab, setTab] = useState('entry')
  const [refreshKey, setRefreshKey] = useState(0)

  const tabs = [
    ['entry', t('tabEntry')],
    ['journal', t('tabJournal')],
    ['accounts', t('tabAccounts')],
  ]

  return (
    <>
      <div className="empresa-cabecera">
        <button className="secundario" onClick={onBack}>← {t('back')}</button>
        <div>
          <strong>{company.name}</strong>
          <span>{t(`territory.${company.tax_territory}`)}</span>
        </div>
      </div>

      <nav className="pestanas">
        {tabs.map(([id, label]) => (
          <button key={id} className={tab === id ? 'activa' : ''} onClick={() => setTab(id)}>{label}</button>
        ))}
      </nav>

      {tab === 'entry' && <JournalEntryForm company={company} onPosted={() => setRefreshKey((k) => k + 1)} />}
      {tab === 'journal' && <GeneralJournal company={company} refreshKey={refreshKey} />}
      {tab === 'accounts' && <Accounts company={company} />}
    </>
  )
}