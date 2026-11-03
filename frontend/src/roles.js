// v0.58.0 · Qué puede hacer cada rol en una empresa compartida (pantalla Accesos). Es la misma matriz que exige la
// prueba de la base de datos (fase 79) y que publica docs/permisos.md; un test comprueba que no se separan.
export const ROLE_ACTIONS = ['see', 'post', 'close', 'ai', 'delete']

// La acción de la matriz (docs/permisos.md) que representa cada capacidad
export const MATRIX_ACTION = {
  see: 'ver la empresa',
  post: 'contabilizar un borrador',
  close: 'cerrar el ejercicio',
  ai: 'Analista: gastar una consulta',
  delete: 'borrar la empresa',
}

// La columna de la matriz de cada rol
export const MATRIX_COLUMN = { admin: 'Administrador', accountant: 'Contable', data_owner: 'Titular de los datos', viewer: 'Lector' }

export const ROLE_CAPS = {
  admin:      { see: true, post: true, close: true, ai: true, delete: true },
  accountant: { see: true, post: true, close: false, ai: false, delete: false },
  data_owner: { see: true, post: true, close: false, ai: true, delete: false },
  viewer:     { see: true, post: false, close: false, ai: false, delete: false },
}
