// Textos de la interfaz en español. La clave (izquierda) es igual en todos los idiomas.
export default {
  appTitle: 'Mini ERP · Contabilidad',
  language: 'Idioma',

  // Acceso
  login: 'Acceso',
  email: 'Correo',
  password: 'Contraseña (mín. 6)',
  signIn: 'Entrar',
  signUp: 'Registrarme',
  signOut: 'Salir',
  userCreated: 'Usuario creado. Si no entras solo, pulsa Entrar.',

  // Empresas
  myCompanies: 'Mis empresas',
  noCompanies: 'Aún no tienes empresas.',
  newCompany: 'Nueva empresa',
  companyName: 'Nombre',
  vatNo: 'NIF',
  createCompany: 'Crear empresa',

    // Pantalla de empresa
  back: 'Empresas',
  tabEntry: 'Nuevo asiento',
  tabJournal: 'Libro diario',
  tabAccounts: 'Cuentas',

  // Plan de cuentas
  chartOfAccounts: 'Plan de cuentas',
  searchAccount: 'Buscar por número o nombre…',
  newAccount: 'Nueva subcuenta',
  newAccountHelp: 'Subcuenta de {n} dígitos que empiece por su cuenta del PGC. Ej: 57200001 Banco, 43000001 Cliente.',
  accountNo: 'Número',
  accountNameEs: 'Nombre (español)',
  accountNameEn: 'Nombre en inglés (opcional)',
  createAccount: 'Crear subcuenta',

  // Asientos
  newEntry: 'Nuevo asiento',
  postingDate: 'Fecha',
  documentNo: 'Nº documento',
  entryDescription: 'Concepto del asiento',
  selectAccount: 'Elige subcuenta…',
  noPostingAccounts: 'Primero crea subcuentas en la pestaña Cuentas.',
  debit: 'Debe',
  credit: 'Haber',
  addLine: 'Añadir línea',
  removeLine: 'Quitar línea',
  fillDifference: 'Poner aquí la diferencia',
  balanced: 'Cuadrado',
  difference: 'Diferencia',
  saveDraft: 'Guardar borrador',
  post: 'Contabilizar',
  postedAs: 'Asiento contabilizado con el nº {n}.',
  savedDraft: 'Borrador guardado.',
  noFiscalYear: 'No hay ejercicio abierto para esa fecha.',
  needTwoLines: 'Un asiento necesita al menos 2 líneas con cuenta e importe.',
  needDescription: 'Escribe el concepto del asiento.',
  unbalanced: 'El asiento no cuadra: el Debe debe ser igual al Haber.',

  // Libro diario
  generalJournal: 'Libro diario',
  noEntries: 'Todavía no hay asientos contabilizados.',
  entry: 'Asiento',
  account: 'Cuenta',

  industry: {
    services: 'Servicios',
    retail: 'Comercio minorista',
    manufacturing: 'Industria',
    ecommerce: 'Comercio electrónico',
  },
  territory: {
    canary_islands: 'Canarias (IGIC)',
    mainland: 'Península (IVA)',
  },
}