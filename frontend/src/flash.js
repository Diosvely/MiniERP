// MENSAJE DE UNA PANTALLA A OTRA (v0.47.0): al guardar o contabilizar un asiento, Nuevo asiento se cierra y vuelve a
// «Asientos», que enseña lo que se hizo. Vive en memoria: se lee una vez y se borra.
let pending = null
export const setFlash = (message) => { pending = message }
export function takeFlash() { const m = pending; pending = null; return m }
