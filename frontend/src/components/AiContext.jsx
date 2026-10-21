import { useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { AiCtx } from '../aiContext'

// v0.41.2 · Proveedor del panel de IA de una empresa (lo que comparte: src/aiContext.js)
export function AiProvider({ company, children }) {
  const [allowed, setAllowed] = useState(false)
  const [topic, setTopic] = useState(null)
  const [open, setOpen] = useState(false)
  const [asked, setAsked] = useState(null)
  useEffect(() => {
    let alive = true
    supabase.rpc('ai_status', { p_company: company.id }).then(({ data }) => { if (alive) setAllowed(data?.allowed === true) })
    return () => { alive = false }
  }, [company.id])
  const ask = (tab) => { setAsked(tab); setOpen(true) }
  return <AiCtx.Provider value={{ allowed, topic, setTopic, open, setOpen, asked, ask, setAsked }}>{children}</AiCtx.Provider>
}
