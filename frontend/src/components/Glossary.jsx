import { useState } from 'react'
import { useI18n } from '../i18n'
import { GLOSSARY } from '../glossary'
import { BookOpen } from 'lucide-react'
import { ICON } from '../icons'

const norm = (s) => String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()

// PÁGINA GLOSARIO (#/glosario): todos los términos, con buscador, en el idioma elegido y con su nombre en BC y SAP.
// Se abre desde la cabecera o desde cualquier globo ⓘ, con sesión o sin ella.
export default function Glossary() {
  const { t, language } = useI18n()
  const [q, setQ] = useState('')
  const entries = Object.entries(GLOSSARY)
    .map(([id, g]) => ({ id, ...g, ...(g[language] ?? g.es) }))
    .sort((a, b) => a.term.localeCompare(b.term, language))
  const query = norm(q).trim()
  const shown = query ? entries.filter((e) => norm(`${e.term} ${e.def} ${e.bc} ${e.sap}`).includes(query)) : entries

  return (
    <section className="tarjeta glosario">
      <div className="fila-glosario">
        <button type="button" className="secundario" onClick={() => window.history.back()}>← {t('glossaryBack')}</button>
        <h2><BookOpen {...ICON} /> {t('glossary')}</h2>
      </div>
      <p className="ayuda">{t('glossaryIntro')}</p>
      <label htmlFor="buscar-glosario" className="oculto">{t('search')}</label>
      <input id="buscar-glosario" type="search" placeholder={t('glossarySearch')} value={q} onChange={(e) => setQ(e.target.value)} />
      <p className="ayuda">{t('glossaryCount').replace('{n}', shown.length).replace('{m}', entries.length)}</p>
      <dl>
        {shown.map((e) => (
          <div key={e.id} className="glosario-termino">
            <dt>{e.term}</dt>
            <dd>
              {e.def}
              {e.ex && <span className="globo-ejemplo">{e.ex}</span>}
              <span className="globo-erp">Business Central: {e.bc} · SAP: {e.sap}</span>
            </dd>
          </div>
        ))}
      </dl>
    </section>
  )
}
