import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { useI18n } from '../i18n'
import { deleteCompany } from '../deleteCompany'
import ErrorBox from './ErrorBox'
import { Trash2 } from 'lucide-react'
import { ICON } from '../icons'

// BORRAR LA EMPRESA ENTERA (solo su admin). Pensado para empresas de práctica o importadas para enseñar cómo se importa.
// Como en GitHub ("Danger zone") o al eliminar una empresa en Business Central: se dice qué se va a borrar y,
// para confirmar, hay que escribir el nombre de la empresa. No se puede deshacer.
// La base de datos borra por tandas (0029) y aquí se ve el avance con una barra.
export default function DeleteCompany({ company, onCancel, onDeleted }) {
  const { t, language } = useI18n()
  const num = (n) => Number(n).toLocaleString(language === 'en' ? 'en-GB' : 'es-ES')
  const [counts, setCounts] = useState(null)     // { entries, invoices, partners }
  const [typed, setTyped] = useState('')
  const [left, setLeft] = useState(null)         // asientos que quedan mientras se borra
  const [error, setError] = useState('')

  // Qué se va a borrar: solo se cuentan filas (head: true), no se descargan
  useEffect(() => {
    let alive = true
    const count = (table) => supabase.from(table).select('id', { count: 'exact', head: true }).eq('company_id', company.id)
    Promise.all([count('journal_entries'), count('invoices'), count('business_partners')]).then(([e, i, p]) => {
      if (!alive) return
      const failed = e.error || i.error || p.error
      if (failed) return setError(failed.message)
      setCounts({ entries: e.count ?? 0, invoices: i.count ?? 0, partners: p.count ?? 0 })
    })
    return () => { alive = false }
  }, [company.id])

  const matches = typed.trim() === company.name.trim()
  const busy = left !== null
  const total = counts?.entries ?? 0

  async function run() {
    setError(''); setLeft(total)
    try {
      await deleteCompany(supabase, company.id, setLeft)
      onDeleted()
    } catch (e) {
      setError(e.message ?? String(e)); setLeft(null)
    }
  }

  return (
    <section className="tarjeta zona-peligro" aria-labelledby="borrar-titulo">
      <h2 id="borrar-titulo"><Trash2 {...ICON} /> {t('deleteCompanyTitle')}</h2>
      <p>{t('deleteCompanyIntro').replace('{c}', company.name)}</p>
      {counts && (
        <ul className="borrar-resumen">
          <li>{t('deleteCompanyEntries').replace('{n}', num(counts.entries))}</li>
          <li>{t('deleteCompanyInvoices').replace('{n}', num(counts.invoices))}</li>
          <li>{t('deleteCompanyPartners').replace('{n}', num(counts.partners))}</li>
          <li>{t('deleteCompanyRest')}</li>
        </ul>
      )}
      <p className="aviso">⚠ {t('deleteCompanyWarning')}</p>

      {busy ? (
        <div className="borrado-progreso" role="status">
          <progress max={Math.max(total, 1)} value={Math.max(total - left, 0)} aria-label={t('deleteCompanyTitle')} />
          <span>{t('deleteCompanyProgress').replace('{n}', num(left))}</span>
        </div>
      ) : (
        <>
          <label htmlFor="borrar-nombre">{t('deleteCompanyType').replace('{c}', company.name)}</label>
          <input id="borrar-nombre" value={typed} autoComplete="off" spellCheck={false}
                 onChange={(e) => setTyped(e.target.value)} />
          <div className="fila">
            <button type="button" className="secundario" onClick={onCancel}>{t('cancel')}</button>
            <button type="button" className="peligro" disabled={!matches || !counts} onClick={run}>
              <Trash2 {...ICON} /> {t('deleteCompanyButton')}
            </button>
          </div>
        </>
      )}
      <ErrorBox error={error} company={company} />
    </section>
  )
}
