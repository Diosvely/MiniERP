import { createContext, useContext } from 'react'

// v0.59.1 · El cuadro de diálogo de confirmación (components/Notice.jsx): éxito o error de lo que se crea
export const NoticeCtx = createContext({ success: () => {}, error: () => {} })
export const useNotice = () => useContext(NoticeCtx)
