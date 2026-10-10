import { createContext, useContext, useEffect, useState } from 'react'
import { supabase } from '../supabase'
import es from './es'
import en from './en'

const dictionaries = { es, en }
const I18nContext = createContext(null)

// Idioma inicial: el último elegido en este navegador, o el del navegador, o español
function initialLanguage() {
  const saved = localStorage.getItem('language')
  if (saved === 'es' || saved === 'en') return saved
  return navigator.language?.startsWith('en') ? 'en' : 'es'
}

export function I18nProvider({ session, children }) {
  const [language, setLanguage] = useState(initialLanguage)

  // El lector de pantalla y el traductor del navegador leen el idioma de <html lang>
  useEffect(() => { document.documentElement.lang = language }, [language])

  // Al iniciar sesión, cargamos el idioma guardado en la base de datos (erp.user_settings)
  useEffect(() => {
    if (!session) return
    supabase
      .from('user_settings')
      .select('language')
      .maybeSingle()
      .then(({ data }) => {
        if (data?.language) {
          setLanguage(data.language)
          localStorage.setItem('language', data.language)
        }
      })
  }, [session])

  // Cambiar idioma: en pantalla, en el navegador y (si hay sesión) en la base de datos
  async function changeLanguage(newLanguage) {
    setLanguage(newLanguage)
    localStorage.setItem('language', newLanguage)
    if (session) {
      await supabase.from('user_settings').upsert({
        user_id: session.user.id,
        language: newLanguage,
        updated_at: new Date().toISOString(),
      })
    }
  }

  // t('industry.retail') → busca la clave en el diccionario del idioma actual
  function t(key) {
    const value = key.split('.').reduce((obj, part) => obj?.[part], dictionaries[language])
    return value ?? key
  }

  return (
    <I18nContext.Provider value={{ language, changeLanguage, t }}>
      {children}
    </I18nContext.Provider>
  )
}

export const useI18n = () => useContext(I18nContext)