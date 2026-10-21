import { createContext, useContext, useEffect } from 'react'

// v0.41.2 · Lo que comparten el panel de IA y las pantallas (el proveedor está en components/AiContext.jsx):
//   allowed  → ¿puede usar la IA en esta empresa? (erp.ai_status: el owner, o el titular de los datos con su cuota)
//   topic    → lo que la pantalla abierta le pasa al panel (el Analista necesita el ejercicio del EFE o de los Ratios)
//   open / ask(tab) → abrir el panel desde una pantalla, en una pestaña
export const AiCtx = createContext({ allowed: false, topic: null, setTopic: () => {}, open: false, setOpen: () => {}, asked: null, ask: () => {}, setAsked: () => {} })
export const useAi = () => useContext(AiCtx)

// Una pantalla le dice al panel de qué puede hablar (y lo quita al cerrarse)
export function useAiTopic(topic) {
  const { setTopic } = useAi()
  const key = JSON.stringify(topic)
  useEffect(() => {
    setTopic(topic)
    return () => setTopic(null)
  }, [key])   // eslint-disable-line react-hooks/exhaustive-deps
}
