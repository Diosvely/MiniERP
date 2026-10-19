// FUENTES → SQL: genera las filas de erp.sources (copia de src/sources.js en la base de datos, para las comprobaciones y
// el chat). sources.test.js comprueba que la última migración con cada fuente coincide con src/sources.js.
// Para regenerarlas, desde la carpeta frontend:
//   node -e "import('./tests/sourcesSql.js').then(async m => console.log(m.sourcesValues((await import('./src/sources.js')).SOURCES)))"
const q = (v) => (v == null ? 'null' : `'${String(v).replace(/'/g, "''")}'`)

// Una fila: (key, issuer, url, checked, title, ref, title_en, ref_en)
export function sourceRow(key, s) {
  return `(${[q(key), q(s.issuer), q(s.url), q(s.checked), q(s.es.title), q(s.es.ref), q(s.en.title), q(s.en.ref)].join(', ')})`
}

export function sourcesValues(sources) {
  return Object.entries(sources).map(([k, s]) => sourceRow(k, s)).join(',\n')
}
