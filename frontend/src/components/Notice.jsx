import { useCallback, useEffect, useRef, useState } from 'react'
import { CheckCircle2 } from 'lucide-react'
import { useI18n } from '../i18n'
import { ICON } from '../icons'
import ErrorBox from './ErrorBox'
import { NoticeCtx } from '../notice'

// v0.59.1 · CONFIRMACIÓN de lo que se crea: un cuadro de diálogo que hay que cerrar, como el MessageBox de SAP Fiori o
// el diálogo de Business Central. Si sale bien, qué se ha creado; si sale mal, el error en lenguaje claro.
//   const notice = useNotice()   (de ../notice)
//   notice.success({ title, lines: ['463 asientos'], action: { label: 'Abrir', onClick } })
//   notice.error(error, { company, before: 'La empresa está creada, pero…' })
export function NoticeProvider({ children }) {
  const [notice, setNotice] = useState(null)   // { kind: 'success' | 'error', … }
  const success = useCallback((n) => setNotice({ kind: 'success', ...n }), [])
  const error = useCallback((err, opts = {}) => setNotice({ kind: 'error', error: err, ...opts }), [])
  return (
    <NoticeCtx.Provider value={{ success, error }}>
      {children}
      {notice && <NoticeDialog notice={notice} onClose={() => setNotice(null)} />}
    </NoticeCtx.Provider>
  )
}

function NoticeDialog({ notice, onClose }) {
  const { t } = useI18n()
  const okRef = useRef(null)
  // el foco va al botón (Intro o Esc cierran) y vuelve a donde estaba al cerrar
  useEffect(() => {
    const before = document.activeElement
    okRef.current?.focus()
    const keys = (e) => { if (e.key === 'Escape') onClose() }
    window.addEventListener('keydown', keys)
    return () => { window.removeEventListener('keydown', keys); before?.focus?.() }
  }, [onClose])
  const ok = notice.kind === 'success'
  return (
    <div className="dialogo-fondo">
      <div className={`dialogo ${ok ? 'dialogo-exito' : 'dialogo-error'}`} role={ok ? 'dialog' : 'alertdialog'} aria-modal="true"
           aria-labelledby="dialogo-titulo">
        {ok ? (
          <>
            <h2 id="dialogo-titulo"><CheckCircle2 {...ICON} /> {notice.title}</h2>
            {(notice.lines ?? []).filter(Boolean).map((l) => <p key={l}>{l}</p>)}
          </>
        ) : (
          <>
            <h2 id="dialogo-titulo" className="sr-solo">{t('notice.errorTitle')}</h2>
            {notice.before && <p className="aviso">{notice.before}</p>}
            <ErrorBox error={notice.error} company={notice.company} />
          </>
        )}
        <div className="dialogo-botones">
          {notice.action && (
            <button type="button" onClick={() => { onClose(); notice.action.onClick() }}>{notice.action.label}</button>)}
          <button type="button" ref={okRef} className={notice.action ? 'secundario' : ''} onClick={onClose}>{t('notice.ok')}</button>
        </div>
      </div>
    </div>
  )
}
