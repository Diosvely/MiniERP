// Paso 218 · v0.41.2 · Panel de IA tipo chat: botón abajo a la derecha con el Tutor (conversación, «Pasar al asiento») y el Analista
// Cambia solo los trozos necesarios (con unas líneas de contexto) y crea los ficheros nuevos.
// Uso (desde la carpeta frontend):   node aplicar-paso218-web.mjs
// Se puede ejecutar dos veces sin problema. Si algo no encaja, lo dice y no toca ese trozo.
import fs from 'node:fs'

const NEW_FILES = {
  "src/aiContext.js": "import { createContext, useContext, useEffect } from 'react'\n\n// v0.41.2 · Lo que comparten el panel de IA y las pantallas (el proveedor está en components/AiContext.jsx):\n//   allowed  → ¿puede usar la IA en esta empresa? (erp.ai_status: el owner, o el titular de los datos con su cuota)\n//   topic    → lo que la pantalla abierta le pasa al panel (el Analista necesita el ejercicio del EFE o de los Ratios)\n//   open / ask(tab) → abrir el panel desde una pantalla, en una pestaña\nexport const AiCtx = createContext({ allowed: false, topic: null, setTopic: () => {}, open: false, setOpen: () => {}, asked: null, ask: () => {}, setAsked: () => {} })\nexport const useAi = () => useContext(AiCtx)\n\n// Una pantalla le dice al panel de qué puede hablar (y lo quita al cerrarse)\nexport function useAiTopic(topic) {\n  const { setTopic } = useAi()\n  const key = JSON.stringify(topic)\n  useEffect(() => {\n    setTopic(topic)\n    return () => setTopic(null)\n  }, [key])   // eslint-disable-line react-hooks/exhaustive-deps\n}\n",
  "src/aiPanel.js": "// PANEL DE IA (v0.41.2): un botón abajo a la derecha abre un panel lateral con las IA de la app, como el chat de una\n// web. Va aparte, sin React, para probarlo (tests/aiPanel.test.js).\n\n// Pestañas del panel: el Tutor de asientos (en cualquier pantalla, si se puede escribir) y el Analista (solo cuando\n// la pantalla abierta le pasa su ejercicio: el EFE y los Ratios)\nexport function panelTabs({ canWrite, topic }) {\n  const tabs = []\n  if (canWrite) tabs.push('tutor')\n  tabs.push('analyst')\n  return tabs.map((id) => ({ id, ready: id === 'tutor' || topic?.kind === 'analyst' }))\n}\n\n// La pestaña que se abre: la que pide la pantalla (botón «Interpretar con el Analista»), o el Analista si la pantalla\n// lo tiene, o el Tutor\nexport function defaultTab({ canWrite, topic, asked }) {\n  if (asked) return asked\n  if (topic?.kind === 'analyst') return 'analyst'\n  return canWrite ? 'tutor' : 'analyst'\n}\n\n// Conversación del Tutor: se guardan las últimas 20 preguntas (solo en esta pestaña del navegador, nunca en la base\n// de datos: lo que escribes puede llevar nombres de terceros)\nexport const MAX_MESSAGES = 20\nexport const addMessage = (msgs, msg) => [...msgs, msg].slice(-MAX_MESSAGES)\nexport const updateMessage = (msgs, id, patch) => msgs.map((m) => (m.id === id ? { ...m, ...patch } : m))\n\n// Enter envía la pregunta; Mayús + Enter hace un salto de línea\nexport const sendsOnKey = (e) => e.key === 'Enter' && !e.shiftKey && !e.isComposing\n",
  "src/components/AiContext.jsx": "import { useEffect, useState } from 'react'\nimport { supabase } from '../supabase'\nimport { AiCtx } from '../aiContext'\n\n// v0.41.2 · Proveedor del panel de IA de una empresa (lo que comparte: src/aiContext.js)\nexport function AiProvider({ company, children }) {\n  const [allowed, setAllowed] = useState(false)\n  const [topic, setTopic] = useState(null)\n  const [open, setOpen] = useState(false)\n  const [asked, setAsked] = useState(null)\n  useEffect(() => {\n    let alive = true\n    supabase.rpc('ai_status', { p_company: company.id }).then(({ data }) => { if (alive) setAllowed(data?.allowed === true) })\n    return () => { alive = false }\n  }, [company.id])\n  const ask = (tab) => { setAsked(tab); setOpen(true) }\n  return <AiCtx.Provider value={{ allowed, topic, setTopic, open, setOpen, asked, ask, setAsked }}>{children}</AiCtx.Provider>\n}\n",
  "src/components/AiPanel.jsx": "import { useEffect, useRef, useState } from 'react'\nimport { useI18n } from '../i18n'\nimport { useAi } from '../aiContext'\nimport EntryTutor from './EntryTutor'\nimport AiAnalyst from './AiAnalyst'\nimport Link from './Link'\nimport { companyPath } from '../router'\nimport { defaultTab, panelTabs } from '../aiPanel'\n\n// PANEL DE IA (v0.41.2): botón flotante abajo a la derecha que abre un panel lateral (en el móvil, a pantalla\n// completa) con las IA de la app, como el chat de una web:\n//   · Tutor de asientos: una conversación; «Pasar al asiento» lleva la propuesta a Nuevo asiento\n//   · Analista: interpreta el ejercicio de la pantalla abierta (EFE o Ratios)\n// El panel no tapa nada en el PC ancho: se pone al lado. Escape lo cierra y el foco vuelve al botón.\n// La conversación se queda mientras la empresa esté abierta (el panel solo se oculta) y no se guarda en ningún sitio.\nexport default function AiPanel({ company, canWrite, onDraft }) {\n  const { t } = useI18n()\n  const { allowed, topic, open, setOpen, asked, setAsked } = useAi()\n  const [tab, setTab] = useState('tutor')\n  const buttonRef = useRef(null)\n  const panelRef = useRef(null)\n  const tabs = panelTabs({ canWrite, topic })\n\n  // Al abrir: la pestaña que pidió la pantalla (o la que toca) y el foco dentro del panel\n  useEffect(() => {\n    if (!open) return\n    setTab(defaultTab({ canWrite, topic, asked }))   // eslint-disable-line react-hooks/set-state-in-effect\n    setAsked(null)\n  }, [open])   // eslint-disable-line react-hooks/exhaustive-deps\n  // …y el foco en la caja de texto del Tutor (o en la pestaña abierta)\n  useEffect(() => {\n    if (!open) return\n    const box = panelRef.current?.querySelector(`#contenido-${tab} textarea`)\n    ;(box ?? panelRef.current?.querySelector('[role=\"tab\"][aria-selected=\"true\"]'))?.focus()\n  }, [open, tab])\n\n  // Al cerrar, el foco vuelve al botón (en el móvil el botón estaba oculto: se espera a que vuelva a verse)\n  function close() { setOpen(false); requestAnimationFrame(() => buttonRef.current?.focus()) }\n  // «Pasar al asiento»: en el PC ancho el panel se queda al lado; si tapa la pantalla (móvil, portátil), se cierra\n  function draft(d) {\n    onDraft(d)\n    if (!window.matchMedia?.('(min-width: 1100px)').matches) setOpen(false)\n  }\n\n  if (!allowed) return null\n  return (\n    <>\n      <button ref={buttonRef} type=\"button\" className=\"boton-ia\" aria-expanded={open} aria-controls=\"panel-ia\"\n              onClick={() => (open ? close() : setOpen(true))} title={t('aiPanelOpen')}>\n        <span aria-hidden=\"true\">✨</span> <span className=\"boton-ia-texto\">{t('aiPanelButton')}</span>\n      </button>\n      <aside id=\"panel-ia\" ref={panelRef} className=\"panel-ia\" hidden={!open} aria-label={t('aiPanelTitle')}\n             onKeyDown={(e) => { if (e.key === 'Escape') close() }}>\n        <div className=\"panel-ia-cabecera\">\n          <strong>✨ {t('aiPanelTitle')}</strong>\n          <button type=\"button\" className=\"secundario cerrar\" onClick={close} aria-label={t('aiPanelClose')}>✕</button>\n        </div>\n        <div role=\"tablist\" className=\"panel-ia-pestanas\" aria-label={t('aiPanelTitle')}>\n          {tabs.map((x) => (\n            <button key={x.id} type=\"button\" role=\"tab\" id={`pestana-${x.id}`} aria-selected={tab === x.id}\n                    aria-controls={`contenido-${x.id}`} className={tab === x.id ? 'activa' : ''} onClick={() => setTab(x.id)}>\n              {t(x.id === 'tutor' ? 'tutorTitle' : 'aiTitle')}\n            </button>\n          ))}\n        </div>\n        {/* El Tutor se queda montado (oculto) para no perder la conversación al cambiar de pestaña o de pantalla */}\n        {canWrite && (\n          <div role=\"tabpanel\" id=\"contenido-tutor\" aria-labelledby=\"pestana-tutor\" hidden={tab !== 'tutor'} className=\"panel-ia-contenido\">\n            <EntryTutor company={company} onLoad={draft} />\n          </div>\n        )}\n        <div role=\"tabpanel\" id=\"contenido-analyst\" aria-labelledby=\"pestana-analyst\" hidden={tab !== 'analyst'} className=\"panel-ia-contenido\">\n          {topic?.kind === 'analyst'\n            ? <AiAnalyst key={`${company.id}-${topic.year}`} company={company} year={topic.year} inPanel />\n            : (\n              <p className=\"ayuda\">\n                {t('aiPanelAnalystWhere')}{' '}\n                <Link to={companyPath(company.id, 'cashflow')} className=\"enlace\">{t('nav.cashflow.label')}</Link>{' · '}\n                <Link to={companyPath(company.id, 'ratios')} className=\"enlace\">{t('nav.ratios.label')}</Link>\n              </p>\n            )}\n        </div>\n      </aside>\n    </>\n  )\n}\n\n// En la pantalla (EFE, Ratios): el botón que abre el panel en el Analista con el ejercicio que estás viendo\nexport function AskAnalyst() {\n  const { t } = useI18n()\n  const { allowed, ask } = useAi()\n  if (!allowed) return null\n  return (\n    <p className=\"pedir-ia\">\n      <button type=\"button\" className=\"secundario\" onClick={() => ask('analyst')}>✨ {t('aiPanelAskAnalyst')}</button>\n    </p>\n  )\n}\n",
  "tests/aiPanel.test.js": "import { describe, expect, it } from 'vitest'\nimport { MAX_MESSAGES, addMessage, defaultTab, panelTabs, sendsOnKey, updateMessage } from '../src/aiPanel'\nimport es from '../src/i18n/es.js'\nimport en from '../src/i18n/en.js'\n\ndescribe('panel de IA (v0.41.2)', () => {\n  it('pestañas: el Tutor si se puede escribir; el Analista siempre, listo solo si la pantalla le pasa su ejercicio', () => {\n    expect(panelTabs({ canWrite: true, topic: null })).toEqual([{ id: 'tutor', ready: true }, { id: 'analyst', ready: false }])\n    expect(panelTabs({ canWrite: true, topic: { kind: 'analyst', year: 2026 } })[1]).toEqual({ id: 'analyst', ready: true })\n    expect(panelTabs({ canWrite: false, topic: null }).map((x) => x.id)).toEqual(['analyst'])\n  })\n  it('pestaña al abrir: la pedida; si no, el Analista en el EFE / Ratios; si no, el Tutor', () => {\n    expect(defaultTab({ canWrite: true, topic: { kind: 'analyst', year: 2026 }, asked: 'tutor' })).toBe('tutor')\n    expect(defaultTab({ canWrite: true, topic: { kind: 'analyst', year: 2026 }, asked: null })).toBe('analyst')\n    expect(defaultTab({ canWrite: true, topic: null, asked: null })).toBe('tutor')\n    expect(defaultTab({ canWrite: false, topic: null, asked: null })).toBe('analyst')\n  })\n  it('la conversación guarda las últimas 20 preguntas y actualiza la respuesta de cada una', () => {\n    let m = []\n    for (let i = 1; i <= 25; i++) m = addMessage(m, { id: i, text: `p${i}` })\n    expect(m).toHaveLength(MAX_MESSAGES)\n    expect(m[0].id).toBe(6)\n    m = updateMessage(m, 25, { result: { ok: true } })\n    expect(m.at(-1)).toEqual({ id: 25, text: 'p25', result: { ok: true } })\n    expect(m[0]).toEqual({ id: 6, text: 'p6' })\n  })\n  it('Enter envía; Mayús + Enter y la escritura con acentos compuestos no', () => {\n    expect(sendsOnKey({ key: 'Enter', shiftKey: false })).toBe(true)\n    expect(sendsOnKey({ key: 'Enter', shiftKey: true })).toBe(false)\n    expect(sendsOnKey({ key: 'Enter', shiftKey: false, isComposing: true })).toBe(false)\n    expect(sendsOnKey({ key: 'a', shiftKey: false })).toBe(false)\n  })\n  it('textos en los dos idiomas', () => {\n    for (const k of ['aiPanelButton', 'aiPanelTitle', 'aiPanelClose', 'aiPanelAsk', 'aiPanelAskAnalyst', 'aiPanelYear', 'tutorLoadedPanel', 'aiYou']) {\n      expect(es[k], k).toBeTruthy()\n      expect(en[k], k).toBeTruthy()\n    }\n  })\n})\n"
}
const EDITS = [
  [
    "src/components/AiAnalyst.jsx",
    "// Lo ven el propietario y el titular de los datos de la empresa (erp.ai_status, con cuota diaria). La IA no cambia nada.\nexport default function AiAnalyst({ company, year }) {\n  const { t, language } = useI18n()\n",
    "// Lo ven el propietario y el titular de los datos de la empresa (erp.ai_status, con cuota diaria). La IA no cambia nada.\n// v0.41.2: vive en el panel de IA (inPanel); la pantalla (EFE, Ratios) le pasa el ejercicio\nexport default function AiAnalyst({ company, year, inPanel = false }) {\n  const { t, language } = useI18n()\n"
  ],
  [
    "src/components/AiAnalyst.jsx",
    "  return (\n    <section className=\"tarjeta analista-ia\">\n      <h2>🤖 {t('aiTitle')} · {year}</h2>\n      <p className=\"ayuda\">{t('aiIntro')}</p>\n",
    "  return (\n    <section className={inPanel ? 'chat-ia analista-ia en-panel' : 'tarjeta analista-ia'}>\n      {inPanel ? <h3>{t('aiPanelYear').replace('{y}', year)}</h3> : <h2>🤖 {t('aiTitle')} · {year}</h2>}\n      <p className=\"ayuda\">{t('aiIntro')}</p>\n"
  ],
  [
    "src/components/CashFlow.jsx",
    "import { money } from '../format'\nimport AiAnalyst from './AiAnalyst'\nimport ErrorBox from './ErrorBox'\n",
    "import { money } from '../format'\nimport { AskAnalyst } from './AiPanel'\nimport { useAiTopic } from '../aiContext'\nimport ErrorBox from './ErrorBox'\n"
  ],
  [
    "src/components/CashFlow.jsx",
    "  const [year, setYear] = useState(() => workYear(company))   // año de la fecha de trabajo\n  const [method, setMethod] = useState('indirect')\n",
    "  const [year, setYear] = useState(() => workYear(company))   // año de la fecha de trabajo\n  useAiTopic({ kind: 'analyst', year: Number(year) })   // v0.41.2: el Analista del panel de IA interpreta este ejercicio\n  const [method, setMethod] = useState('indirect')\n"
  ],
  [
    "src/components/CashFlow.jsx",
    "      )}\n      {check && <AiAnalyst company={company} year={year} />}\n    </>\n",
    "      )}\n      {check && <AskAnalyst />}\n    </>\n"
  ],
  [
    "src/components/CompanyView.jsx",
    "import Ratios from './Ratios'\nimport EntryTutor from './EntryTutor'\nimport CompanyAccess from './CompanyAccess'\n",
    "import Ratios from './Ratios'\nimport AiPanel from './AiPanel'\nimport { AiProvider } from './AiContext'\nimport CompanyAccess from './CompanyAccess'\n"
  ],
  [
    "src/components/CompanyView.jsx",
    "\n  return (\n",
    "\n  // v0.41.2 · «Pasar al asiento» desde el Tutor del panel: lleva la propuesta a Nuevo asiento (estés donde estés)\n  function draftFromTutor(d) {\n    setDraft(d)\n    if (section !== 'entry') go('entry')\n  }\n\n  return (\n"
  ],
  [
    "src/components/CompanyView.jsx",
    "  return (\n    <div className=\"empresa-layout\">\n",
    "  return (\n    <AiProvider company={company}>\n    <div className=\"empresa-layout\">\n"
  ],
  [
    "src/components/CompanyView.jsx",
    "        {section === 'home' && <Home company={company} readOnly={readOnly} mode={mode} onAuditor={() => setMode('auditor')} />}\n        {section === 'entry' && !readOnly && <EntryTutor company={company} onLoad={setDraft} />}\n        {section === 'entry' && !readOnly && (\n",
    "        {section === 'home' && <Home company={company} readOnly={readOnly} mode={mode} onAuditor={() => setMode('auditor')} />}\n        {section === 'entry' && !readOnly && (\n"
  ],
  [
    "src/components/CompanyView.jsx",
    "      </section>\n    </div>\n",
    "      </section>\n      <AiPanel company={company} canWrite={!readOnly} onDraft={draftFromTutor} />\n    </div>\n"
  ],
  [
    "src/components/CompanyView.jsx",
    "    </div>\n  )\n",
    "    </div>\n    </AiProvider>\n  )\n"
  ],
  [
    "src/components/EntryTutor.jsx",
    "import { useEffect, useState } from 'react'\nimport { supabase } from '../supabase'\n",
    "import { useEffect, useRef, useState } from 'react'\nimport { supabase } from '../supabase'\n"
  ],
  [
    "src/components/EntryTutor.jsx",
    "import ErrorBox from './ErrorBox'\n\n",
    "import ErrorBox from './ErrorBox'\nimport { addMessage, sendsOnKey, updateMessage } from '../aiPanel'\n\n"
  ],
  [
    "src/components/EntryTutor.jsx",
    "// Tutor de asientos con IA: describes la operación, la IA propone el asiento, el ERP lo comprueba y tú decides.\n// \"Cargar en el asiento\" crea las subcuentas nuevas que hagan falta y pasa las líneas al formulario de abajo:\n// nada se contabiliza sin que lo revises. Lo ven el propietario y el titular de los datos (erp.ai_status, con cuota diaria).\nexport default function EntryTutor({ company, onLoad }) {\n",
    "// Tutor de asientos con IA: describes la operación, la IA propone el asiento, el ERP lo comprueba y tú decides.\n// v0.41.2: es una conversación dentro del panel de IA (abajo a la derecha). «Pasar al asiento» crea las subcuentas\n// nuevas que hagan falta y lleva las líneas al formulario de Nuevo asiento: nada se contabiliza sin que lo revises.\n// Lo ven el propietario y el titular de los datos (erp.ai_status, con cuota diaria). La conversación no se guarda.\nexport default function EntryTutor({ company, onLoad }) {\n"
  ],
  [
    "src/components/EntryTutor.jsx",
    "  const [text, setText] = useState('')\n  const [result, setResult] = useState(null)\n  const [busy, setBusy] = useState(false)\n",
    "  const [text, setText] = useState('')\n  const [msgs, setMsgs] = useState([])   // [{ id, text, result, where, error }] · las últimas 20, solo en memoria\n  const [busy, setBusy] = useState(false)\n"
  ],
  [
    "src/components/EntryTutor.jsx",
    "  const [busy, setBusy] = useState(false)\n  const [loading, setLoading] = useState(false)\n  const [error, setError] = useState('')\n  const [where, setWhere] = useState(null)   // v0.40.0: la operación del catálogo (erp.operations) a la que se parece el asiento\n\n",
    "  const [busy, setBusy] = useState(false)\n  const [loading, setLoading] = useState(null)   // id del mensaje que se está pasando al asiento\n  const [loaded, setLoaded] = useState(null)     // id del último que se pasó\n  const endRef = useRef(null)\n\n"
  ],
  [
    "src/components/EntryTutor.jsx",
    "  const remaining = status?.limit == null ? null : Math.max(0, status.limit - status.used)\n  useEffect(() => { setResult(null); setError('') }, [company.id])\n\n  const m = (v) => money(v, language)\n\n",
    "  const remaining = status?.limit == null ? null : Math.max(0, status.limit - status.used)\n  useEffect(() => { setMsgs([]) }, [company.id])   // otra empresa: otra conversación\n  useEffect(() => { endRef.current?.scrollIntoView?.({ block: 'end' }) }, [msgs.length, busy])\n\n"
  ],
  [
    "src/components/EntryTutor.jsx",
    "  async function propose() {\n    setBusy(true); setError(''); setResult(null); setWhere(null)\n    try {\n",
    "  async function propose() {\n    const question = text.trim()\n    if (question.length < 5 || busy) return\n    const id = Date.now()\n    setMsgs((m) => addMessage(m, { id, text: question }))\n    setText(''); setBusy(true)\n    try {\n"
  ],
  [
    "src/components/EntryTutor.jsx",
    "        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${session?.access_token ?? ''}` },\n        body: JSON.stringify({ company_id: company.id, text, language }),\n      })\n",
    "        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${session?.access_token ?? ''}` },\n        body: JSON.stringify({ company_id: company.id, text: question, language }),\n      })\n"
  ],
  [
    "src/components/EntryTutor.jsx",
    "      if (!res.ok) throw new Error(t(`aiError.${body.error}`) + (body.detail ? ` (${body.detail})` : ''))\n      setResult(body)\n      // ¿Dónde se registra en el ERP? (si la base de datos aún no tiene el catálogo, no se enseña)\n",
    "      if (!res.ok) throw new Error(t(`aiError.${body.error}`) + (body.detail ? ` (${body.detail})` : ''))\n      setMsgs((m) => updateMessage(m, id, { result: body }))\n      // ¿Dónde se registra en el ERP? (si la base de datos aún no tiene el catálogo, no se enseña)\n"
  ],
  [
    "src/components/EntryTutor.jsx",
    "      supabase.rpc('operation_for_lines', { p_lines: lines.map((l) => ({ account_no: l.account_no, debit: l.debit, credit: l.credit })) })\n        .then(({ data }) => setWhere(Array.isArray(data) ? data[0] ?? null : null))\n    } catch (e) {\n",
    "      supabase.rpc('operation_for_lines', { p_lines: lines.map((l) => ({ account_no: l.account_no, debit: l.debit, credit: l.credit })) })\n        .then(({ data }) => setMsgs((m) => updateMessage(m, id, { where: Array.isArray(data) ? data[0] ?? null : null })))\n    } catch (e) {\n"
  ],
  [
    "src/components/EntryTutor.jsx",
    "    } catch (e) {\n      setError(e.message)\n    } finally {\n",
    "    } catch (e) {\n      setMsgs((m) => updateMessage(m, id, { error: e.message }))\n    } finally {\n"
  ],
  [
    "src/components/EntryTutor.jsx",
    "\n  // Crea las subcuentas nuevas (217 → 21700001…) y pasa el asiento al formulario\n  async function load() {\n    setLoading(true); setError('')\n    const v = result.validation\n    for (const l of v.lines.filter((x) => x.new_account)) {\n",
    "\n  // Crea las subcuentas nuevas (217 → 21700001…) y pasa el asiento al formulario de Nuevo asiento\n  async function load(msg) {\n    setLoading(msg.id)\n    const v = msg.result.validation\n    for (const l of v.lines.filter((x) => x.new_account)) {\n"
  ],
  [
    "src/components/EntryTutor.jsx",
    "      if (error && !/duplicate|already exists|ya existe/i.test(error.message)) {\n        setLoading(false)\n        return setError(error.message)\n      }\n",
    "      if (error && !/duplicate|already exists|ya existe/i.test(error.message)) {\n        setLoading(null)\n        return setMsgs((m) => updateMessage(m, msg.id, { error: error.message }))\n      }\n"
  ],
  [
    "src/components/EntryTutor.jsx",
    "    }\n    setLoading(false)\n    onLoad({\n",
    "    }\n    setLoading(null); setLoaded(msg.id)\n    onLoad({\n"
  ],
  [
    "src/components/EntryTutor.jsx",
    "      id: Date.now(),\n      description: text.slice(0, 120),\n      lines: v.lines.map((l) => ({ account_no: l.account_no, debit: l.debit, credit: l.credit, description: l.description })),\n",
    "      id: Date.now(),\n      description: msg.text.slice(0, 120),\n      lines: v.lines.map((l) => ({ account_no: l.account_no, debit: l.debit, credit: l.credit, description: l.description })),\n"
  ],
  [
    "src/components/EntryTutor.jsx",
    "    })\n    window.scrollTo?.({ top: document.querySelector('.formulario-asiento')?.offsetTop ?? 0, behavior: 'smooth' })\n  }\n",
    "    })\n  }\n"
  ],
  [
    "src/components/EntryTutor.jsx",
    "\n  if (!allowed) return null\n  const p = result?.proposal\n  const v = result?.validation\n  const icon = { error: '✕', warning: '⚠', info: 'ℹ' }\n\n",
    "\n  if (!allowed) return <p className=\"ayuda\">{t('aiPanelNotAllowed')}</p>\n\n"
  ],
  [
    "src/components/EntryTutor.jsx",
    "  return (\n    <section className=\"tarjeta tutor-asientos\">\n      <h2>🎓 {t('tutorTitle')}</h2>\n      <p className=\"ayuda\">{t('tutorIntro')}</p>\n",
    "  return (\n    <div className=\"chat-ia\">\n      <p className=\"ayuda\">{t('tutorIntro')}</p>\n"
  ],
  [
    "src/components/EntryTutor.jsx",
    "      <p className=\"ayuda\">{t('tutorIntro')}</p>\n      <textarea rows={3} maxLength={1000} value={text} placeholder={t('tutorPlaceholder')}\n                onChange={(e) => setText(e.target.value)} />\n      <button type=\"button\" disabled={busy || text.trim().length < 5 || remaining === 0} onClick={propose}>\n        {busy ? `${t('tutorThinking')}…` : t('tutorPropose')}\n      </button>\n      {busy && <p className=\"ayuda\">{t('aiWait')}</p>}\n      {remaining !== null && <p className=\"ayuda\">{t('aiRemaining').replace('{n}', remaining).replace('{l}', status.limit)}</p>}\n",
    "      <p className=\"ayuda\">{t('tutorIntro')}</p>\n      <ol className=\"chat-mensajes\" aria-live=\"polite\">\n        {msgs.map((msg) => (\n          <li key={msg.id} className=\"chat-turno\">\n            <p className=\"burbuja usuario\"><span className=\"oculto\">{t('aiYou')}: </span>{msg.text}</p>\n            {msg.error && <div className=\"burbuja ia\"><ErrorBox error={msg.error} company={company} /></div>}\n            {!msg.result && !msg.error && <p className=\"burbuja ia escribiendo\">{t('tutorThinking')}… <small>{t('aiWait')}</small></p>}\n            {msg.result && (\n              <div className=\"burbuja ia\">\n                <Proposal company={company} msg={msg} t={t} language={language}\n                          loading={loading === msg.id} loaded={loaded === msg.id} onLoad={() => load(msg)} />\n              </div>\n            )}\n          </li>\n        ))}\n        <li ref={endRef} aria-hidden=\"true\" className=\"chat-fin\" />\n      </ol>\n      {msgs.length === 0 && <p className=\"ayuda chat-vacio\">💬 {t('tutorPlaceholder')}</p>}\n      <form className=\"chat-entrada\" onSubmit={(e) => { e.preventDefault(); propose() }}>\n        <label className=\"oculto\" htmlFor=\"tutor-pregunta\">{t('tutorTitle')}</label>\n        <textarea id=\"tutor-pregunta\" rows={2} maxLength={1000} value={text} placeholder={t('aiPanelAsk')}\n                  onChange={(e) => setText(e.target.value)}\n                  onKeyDown={(e) => { if (sendsOnKey(e)) { e.preventDefault(); propose() } }} />\n        <button type=\"submit\" disabled={busy || text.trim().length < 5 || remaining === 0}>\n          {busy ? `${t('tutorThinking')}…` : t('tutorPropose')}\n        </button>\n      </form>\n      {remaining !== null && <p className=\"ayuda\">{t('aiRemaining').replace('{n}', remaining).replace('{l}', status.limit)}</p>}\n"
  ],
  [
    "src/components/EntryTutor.jsx",
    "      {remaining !== null && <p className=\"ayuda\">{t('aiRemaining').replace('{n}', remaining).replace('{l}', status.limit)}</p>}\n      <ErrorBox error={error} company={company} />\n\n",
    "      {remaining !== null && <p className=\"ayuda\">{t('aiRemaining').replace('{n}', remaining).replace('{l}', status.limit)}</p>}\n    </div>\n  )\n}\n\n"
  ],
  [
    "src/components/EntryTutor.jsx",
    "\n      {p && v && (\n        <div className=\"propuesta\">\n          {p.explanation && <p className=\"resumen-ia\">{p.explanation}</p>}\n          {p.valuation_rule_title && <p><span className=\"etiqueta\">📘 {p.valuation_rule_title}</span></p>}\n          {p.assumptions.length > 0 && (\n            <div className=\"bloque-ia\">\n              <h3>{t('tutorAssumptions')}</h3>\n              <ul>{p.assumptions.map((a, i) => <li key={i}><span className=\"icono\">•</span> {a}</li>)}</ul>\n            </div>\n          )}\n\n          <div className=\"tabla-ancha\">\n            <table className=\"informe\">\n              <thead>\n                <tr><th>{t('account')}</th><th className=\"num\">{t('debit')}</th><th className=\"num\">{t('credit')}</th><th>{t('tutorWhy')}</th></tr>\n              </thead>\n              <tbody>\n                {v.lines.map((l) => (\n                  <tr key={l.line_no}>\n                    <td>\n                      <span className=\"codigo\">{l.account_no}</span> {l.account_name}\n                      {l.new_account && <span className=\"insignia\">{t('tutorNewAccount')}</span>}\n                    </td>\n                    <td className=\"num\">{Number(l.debit) ? m(l.debit) : ''}</td>\n                    <td className=\"num\">{Number(l.credit) ? m(l.credit) : ''}</td>\n                    <td className=\"ayuda\">{l.description}</td>\n                  </tr>\n                ))}\n                <tr className=\"total\">\n                  <td><strong>{t('total')}</strong></td>\n                  <td className=\"num\"><strong>{m(v.debit)}</strong></td>\n                  <td className=\"num\"><strong>{m(v.credit)}</strong></td>\n                  <td />\n                </tr>\n              </tbody>\n            </table>\n          </div>\n\n          {v.checks.length > 0 && (\n            <>\n              <h3>{t('tutorChecks')}</h3>\n              <ul className=\"comprobaciones\">\n                {v.checks.map((c, i) => (\n                  <li key={i} className={c.level}>\n                    <span className=\"icono\">{icon[c.level]}</span> {t(`tutorCheck.${c.code}`).replace('{d}', c.detail ?? '')}\n                  </li>\n                ))}\n              </ul>\n            </>\n          )}\n          {where && (\n            <p className=\"donde-registra\">\n              📍 {t('tutorWhere')}: <strong>{language === 'en' ? where.title_en || where.title : where.title}</strong>\n              {where.screen !== 'entry' && (<> → <Link to={companyPath(company.id, where.screen)} className=\"enlace\">\n                {t(`nav.${where.screen}.label`).replace('{tax}', company.tax_territory === 'canary_islands' ? 'IGIC' : 'IVA').replace('{form}', company.tax_territory === 'canary_islands' ? '420' : '303')}</Link></>)}\n              <small>{t(where.screen === 'entry' ? 'tutorWhereHere' : 'tutorWhereScreen')}</small>\n            </p>\n          )}\n          {result.rounds === 2 && <p className=\"ayuda\">↻ {t('tutorSecondRound')}</p>}\n\n          {p.question && (\n            <div className=\"bloque-ia learning\">\n              <h3>❓ {t('tutorQuestion')}</h3>\n              <p>{p.question}</p>\n            </div>\n          )}\n\n          {v.ok\n            ? <button type=\"button\" disabled={loading} onClick={load}>⬇ {t('tutorLoad')}</button>\n            : <p className=\"aviso\">⚠ {t('tutorCannotLoad')}</p>}\n          <p className=\"ayuda\">{t('tutorDisclaimer').replace('{m}', result.model.replace(/^@cf\\//, ''))}</p>\n          <AiFeedback key={result.proposal?.explanation ?? ''} company={company} kind=\"tutor\" prompt={text} model={result.model}\n                      answer={{ explanation: p.explanation, valuation_rule: p.valuation_rule, assumptions: p.assumptions,\n                                lines: v.lines, checks: v.checks, ok: v.ok }} />\n        </div>\n",
    "\n// La respuesta del Tutor: explicación, asiento comprobado por el ERP, avisos, dónde se registra y «Pasar al asiento»\nfunction Proposal({ company, msg, t, language, loading, loaded, onLoad }) {\n  const { result, where } = msg\n  const p = result.proposal\n  const v = result.validation\n  const m = (x) => money(x, language)\n  const icon = { error: '✕', warning: '⚠', info: 'ℹ' }\n  if (!p || !v) return null\n  return (\n    <div className=\"propuesta\">\n      {p.explanation && <p className=\"resumen-ia\">{p.explanation}</p>}\n      {p.valuation_rule_title && <p><span className=\"etiqueta\">📘 {p.valuation_rule_title}</span></p>}\n      {p.assumptions.length > 0 && (\n        <div className=\"bloque-ia\">\n          <h3>{t('tutorAssumptions')}</h3>\n          <ul>{p.assumptions.map((a, i) => <li key={i}><span className=\"icono\">•</span> {a}</li>)}</ul>\n        </div>\n"
  ],
  [
    "src/components/EntryTutor.jsx",
    "      )}\n    </section>\n  )\n",
    "      )}\n\n      <div className=\"tabla-ancha\" tabIndex={0} role=\"region\" aria-label={t('tutorProposedEntry')}>\n        <table className=\"informe\">\n          <thead>\n            <tr><th>{t('account')}</th><th className=\"num\">{t('debit')}</th><th className=\"num\">{t('credit')}</th></tr>\n          </thead>\n          <tbody>\n            {v.lines.map((l) => (\n              <tr key={l.line_no} title={l.description || undefined}>\n                <td>\n                  <span className=\"codigo\">{l.account_no}</span> {l.account_name}\n                  {l.new_account && <span className=\"insignia\">{t('tutorNewAccount')}</span>}\n                  {l.description && <small className=\"porque\">{l.description}</small>}\n                </td>\n                <td className=\"num\">{Number(l.debit) ? m(l.debit) : ''}</td>\n                <td className=\"num\">{Number(l.credit) ? m(l.credit) : ''}</td>\n              </tr>\n            ))}\n            <tr className=\"total\">\n              <td><strong>{t('total')}</strong></td>\n              <td className=\"num\"><strong>{m(v.debit)}</strong></td>\n              <td className=\"num\"><strong>{m(v.credit)}</strong></td>\n            </tr>\n          </tbody>\n        </table>\n      </div>\n\n      {v.checks.length > 0 && (\n        <>\n          <h3>{t('tutorChecks')}</h3>\n          <ul className=\"comprobaciones\">\n            {v.checks.map((c, i) => (\n              <li key={i} className={c.level}>\n                <span className=\"icono\">{icon[c.level]}</span> {t(`tutorCheck.${c.code}`).replace('{d}', c.detail ?? '')}\n              </li>\n            ))}\n          </ul>\n        </>\n      )}\n      {where && (\n        <p className=\"donde-registra\">\n          📍 {t('tutorWhere')}: <strong>{language === 'en' ? where.title_en || where.title : where.title}</strong>\n          {where.screen !== 'entry' && (<> → <Link to={companyPath(company.id, where.screen)} className=\"enlace\">\n            {t(`nav.${where.screen}.label`).replace('{tax}', company.tax_territory === 'canary_islands' ? 'IGIC' : 'IVA').replace('{form}', company.tax_territory === 'canary_islands' ? '420' : '303')}</Link></>)}\n          <small>{t(where.screen === 'entry' ? 'tutorWhereHere' : 'tutorWhereScreen')}</small>\n        </p>\n      )}\n      {result.rounds === 2 && <p className=\"ayuda\">↻ {t('tutorSecondRound')}</p>}\n\n      {p.question && (\n        <div className=\"bloque-ia learning\">\n          <h3>❓ {t('tutorQuestion')}</h3>\n          <p>{p.question}</p>\n        </div>\n      )}\n\n      {v.ok\n        ? <button type=\"button\" disabled={loading} onClick={onLoad}>⬇ {t('tutorLoad')}</button>\n        : <p className=\"aviso\">⚠ {t('tutorCannotLoad')}</p>}\n      {loaded && <p className=\"exito\" role=\"status\">✓ {t('tutorLoadedPanel')}</p>}\n      <p className=\"ayuda\">{t('tutorDisclaimer').replace('{m}', result.model.replace(/^@cf\\//, ''))}</p>\n      <AiFeedback key={p.explanation ?? ''} company={company} kind=\"tutor\" prompt={msg.text} model={result.model}\n                  answer={{ explanation: p.explanation, valuation_rule: p.valuation_rule, assumptions: p.assumptions,\n                            lines: v.lines, checks: v.checks, ok: v.ok }} />\n    </div>\n  )\n"
  ],
  [
    "src/components/Ratios.jsx",
    "import { money } from '../format'\nimport AiAnalyst from './AiAnalyst'\nimport ErrorBox from './ErrorBox'\n",
    "import { money } from '../format'\nimport { AskAnalyst } from './AiPanel'\nimport { useAiTopic } from '../aiContext'\nimport ErrorBox from './ErrorBox'\n"
  ],
  [
    "src/components/Ratios.jsx",
    "  const [year, setYear] = useState(() => workYear(company))   // año de la fecha de trabajo\n  const [rows, setRows] = useState([])\n",
    "  const [year, setYear] = useState(() => workYear(company))   // año de la fecha de trabajo\n  useAiTopic({ kind: 'analyst', year: Number(year) })   // v0.41.2: el Analista del panel de IA interpreta este ejercicio\n  const [rows, setRows] = useState([])\n"
  ],
  [
    "src/components/Ratios.jsx",
    "      {rows.length > 0 && <p className=\"ayuda\">{t('ratiosNote')}</p>}\n      {rows.length > 0 && <AiAnalyst company={company} year={year} />}\n    </>\n",
    "      {rows.length > 0 && <p className=\"ayuda\">{t('ratiosNote')}</p>}\n      {rows.length > 0 && <AskAnalyst />}\n    </>\n"
  ],
  [
    "src/i18n/en.js",
    "  tutorQuestion: 'Check your understanding',\n  tutorLoad: 'Load into the entry',\n  tutorLoaded: 'Entry loaded from the Tutor: review it, set the date and document, and save or post it.',\n",
    "  tutorQuestion: 'Check your understanding',\n  tutorLoad: 'Move to the entry',\n  tutorLoadedPanel: 'In New entry: review it and post it.',\n  aiPanelButton: 'AI',\n  aiPanelOpen: 'Open the AI panel (Entry tutor and Analyst)',\n  aiPanelTitle: 'AI assistant',\n  aiPanelClose: 'Close the AI panel',\n  aiPanelAsk: 'Describe the transaction… (Enter sends · Shift + Enter, new line)',\n  aiPanelNotAllowed: 'AI in this company is only for its owner and the data owner.',\n  aiPanelAnalystWhere: 'The Analyst interprets the year you are viewing. Open it from:',\n  aiPanelAskAnalyst: 'Interpret this year with the AI Analyst',\n  aiPanelYear: 'Year {y}',\n  aiYou: 'You',\n  tutorProposedEntry: 'Proposed entry',\n  tutorLoaded: 'Entry loaded from the Tutor: review it, set the date and document, and save or post it.',\n"
  ],
  [
    "src/i18n/es.js",
    "  tutorQuestion: 'Comprueba que lo has entendido',\n  tutorLoad: 'Cargar en el asiento',\n  tutorLoaded: 'Asiento cargado desde el Tutor: revísalo, ponle fecha y documento, y guárdalo o contabilízalo.',\n",
    "  tutorQuestion: 'Comprueba que lo has entendido',\n  tutorLoad: 'Pasar al asiento',\n  tutorLoadedPanel: 'En Nuevo asiento: revísalo y contabilízalo.',\n  aiPanelButton: 'IA',\n  aiPanelOpen: 'Abrir el panel de IA (Tutor de asientos y Analista)',\n  aiPanelTitle: 'Asistente IA',\n  aiPanelClose: 'Cerrar el panel de IA',\n  aiPanelAsk: 'Describe la operación… (Enter envía · Mayús + Enter, nueva línea)',\n  aiPanelNotAllowed: 'La IA de esta empresa solo la usan su propietario y el titular de los datos.',\n  aiPanelAnalystWhere: 'El Analista interpreta el ejercicio que estés viendo. Ábrelo desde:',\n  aiPanelAskAnalyst: 'Interpretar este ejercicio con el Analista IA',\n  aiPanelYear: 'Ejercicio {y}',\n  aiYou: 'Tú',\n  tutorProposedEntry: 'Asiento propuesto',\n  tutorLoaded: 'Asiento cargado desde el Tutor: revísalo, ponle fecha y documento, y guárdalo o contabilízalo.',\n"
  ],
  [
    "src/index.css",
    ".ratio-estado { display: inline-block; font-size: .75rem; font-weight: 700; padding: 1px 8px; border-radius: 999px; }\n.ratio-estado.ok { background: rgba(26,127,55,.12); color: var(--exito); }\n.ratio-estado.low, .ratio-estado.high { background: rgba(245,165,36,.18); color: var(--alerta); }\n.ratio-detalle { padding: 0 4px 12px 22px; display: flex; flex-direction: column; gap: 6px; font-size: .9rem; }\n",
    ".ratio-estado { display: inline-block; font-size: .75rem; font-weight: 700; padding: 1px 8px; border-radius: 999px; }\n.ratio-estado.ok { background: rgba(26,127,55,.12); color: color-mix(in srgb, var(--exito) 80%, var(--texto)); }   /* v0.41.2: contraste AA sobre su fondo */\n.ratio-estado.low, .ratio-estado.high { background: rgba(245,165,36,.18); color: color-mix(in srgb, var(--alerta) 55%, var(--texto)); }\n.ratio-detalle { padding: 0 4px 12px 22px; display: flex; flex-direction: column; gap: 6px; font-size: .9rem; }\n"
  ],
  [
    "src/index.css",
    "\n/* --- v0.41.1 · DENSIDAD EN EL PC: letra un poco más pequeña y menos relleno, para que quepa más sin hacer scroll ---\n",
    "\n/* --- v0.41.2 · PANEL DE IA: botón flotante abajo a la derecha y panel lateral (en el móvil, a pantalla completa) --- */\n.boton-ia { position: fixed; right: 20px; bottom: 20px; z-index: 60; border-radius: 999px; padding: 12px 18px;\n            font-weight: 700; box-shadow: 0 6px 20px rgba(0,0,0,.25); display: flex; align-items: center; gap: 6px; }\n.boton-ia[aria-expanded=\"true\"] { background: var(--texto); color: var(--fondo); }\n.panel-ia { position: fixed; z-index: 55; top: 0; right: 0; bottom: 0; width: min(440px, 100vw); display: flex; flex-direction: column;\n            background: var(--tarjeta); border-left: 1px solid var(--borde); box-shadow: -8px 0 24px rgba(0,0,0,.15); }\n.panel-ia[hidden] { display: none; }\n.panel-ia-cabecera { display: flex; align-items: center; justify-content: space-between; padding: 12px 14px; border-bottom: 1px solid var(--borde); }\n.panel-ia-cabecera .cerrar { padding: 4px 10px; }\n.panel-ia-pestanas { display: flex; gap: 4px; padding: 8px 14px 0; border-bottom: 1px solid var(--borde); }\n.panel-ia-pestanas button { background: transparent; color: var(--suave); border-radius: 8px 8px 0 0; border-bottom: 2px solid transparent; }\n.panel-ia-pestanas button.activa { color: var(--primario); border-bottom-color: var(--primario); font-weight: 700; }\n.panel-ia-contenido { flex: 1; overflow-y: auto; padding: 12px 14px 0; }\n.chat-ia { display: flex; flex-direction: column; gap: 10px; }\n.chat-mensajes { display: flex; flex-direction: column; gap: 14px; }\n.chat-mensajes > li { border: 0; padding: 0; }\n.chat-turno { display: flex; flex-direction: column; gap: 6px; }\n.burbuja { margin: 0; padding: 10px 12px; border-radius: 12px; line-height: 1.45; }\n.burbuja.usuario { align-self: flex-end; max-width: 85%; background: var(--primario); color: var(--sobre-color); border-bottom-right-radius: 4px; white-space: pre-wrap; }\n.burbuja.ia { background: var(--fondo); border: 1px solid var(--borde); border-bottom-left-radius: 4px; display: flex; flex-direction: column; gap: 8px; }\n.burbuja.escribiendo { color: var(--suave); }\n.burbuja .propuesta { display: flex; flex-direction: column; gap: 8px; }\n.burbuja table .porque { display: block; color: var(--suave); font-size: .8rem; }\n.chat-entrada { position: sticky; bottom: 0; z-index: 2; display: flex; flex-direction: column; gap: 6px; background: var(--tarjeta);\n               padding: 8px 0; box-shadow: 0 -10px 12px -6px var(--tarjeta); }\n.chat-entrada textarea { width: 100%; resize: vertical; font: inherit; padding: 8px 10px; border-radius: 8px; border: 1px solid var(--borde);\n                         background: var(--tarjeta); color: var(--texto); }\n.chat-entrada button { align-self: flex-end; }\n.en-panel h3 { margin: 0; }\n.analista-ia.en-panel { border-left: 0; }\n.pedir-ia { margin: 0 0 12px; }\n@media (min-width: 1100px) {\n  /* PC ancho: el panel se pone al lado y el contenido deja su sitio (no tapa nada) */\n  .empresa-layout:has(> .panel-ia:not([hidden])) { padding-right: 440px; }\n  .boton-ia[aria-expanded=\"true\"] { right: 460px; }\n}\n@media (max-width: 600px) {\n  .boton-ia { right: 12px; bottom: 12px; padding: 10px 14px; }\n  .boton-ia[aria-expanded=\"true\"] { display: none; }   /* a pantalla completa se cierra con ✕ o Escape */\n}\n@media print { .boton-ia, .panel-ia { display: none !important; } }\n\n/* --- v0.41.1 · DENSIDAD EN EL PC: letra un poco más pequeña y menos relleno, para que quepa más sin hacer scroll ---\n"
  ]
]

let warnings = 0
const read = (f) => fs.readFileSync(f, 'utf8')
// Trabaja con saltos de línea \n y respeta los \r\n del fichero si los tiene (Windows)
const edit = (f, fn) => {
  const raw = read(f)
  const crlf = raw.includes('\r\n')
  const before = raw.replace(/\r\n/g, '\n')
  const after = fn(before)
  if (after !== before) fs.writeFileSync(f, crlf ? after.replace(/\n/g, '\r\n') : after)
}

for (const [f, content] of Object.entries(NEW_FILES)) {
  if (fs.existsSync(f) && read(f).replace(/\r\n/g, '\n') === content) console.log(`· ${f} ya estaba`)
  else { fs.writeFileSync(f, content); console.log(`✓ ${f} creado`) }
}

for (const [f, from, to] of EDITS) {
  edit(f, (s) => {
    if (s.includes(to)) { console.log(`· ${f}: ya estaba cambiado`); return s }
    if (!s.includes(from)) { warnings++; console.log(`⚠ ${f}: no encuentro el trozo que empieza por:\n    ${from.split('\n')[0].trim()}`); return s }
    console.log(`✓ ${f}: ${from.split('\n')[0].trim().slice(0, 70)}…`)
    return s.replace(from, to)
  })
}


console.log(warnings ? `\n⚠ ${warnings} aviso(s): pásame el mensaje y lo vemos.` : '\n✔ Paso 218 aplicado. Ahora: npm run lint · npm test · npm run build')
