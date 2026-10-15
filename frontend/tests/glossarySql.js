// GLOSARIO → SQL: genera las filas de erp.concepts (copia del glosario en la base de datos, para el Tutor y el chat).
// glossary.test.js comprueba que la última migración con cada término coincide con src/glossary.js.
// Para regenerarlas, desde la carpeta frontend:
//   node -e "import('./tests/glossarySql.js').then(async m => console.log(m.conceptsValues((await import('./src/glossary.js')).GLOSSARY)))"
const q = (v) => (v == null ? 'null' : `'${String(v).replace(/'/g, "''")}'`)
const arr = (a) => `'{${(a ?? []).join(',')}}'`

// Una fila: (key, sort, term, definition, example, term_en, definition_en, example_en, bc, sap, pgc)
export function conceptRow(key, g, sort) {
  return `(${[q(key), sort, q(g.es.term), q(g.es.def), q(g.es.ex), q(g.en.term), q(g.en.def), q(g.en.ex), q(g.bc), q(g.sap), arr(g.pgc)].join(', ')})`
}

export function conceptsValues(glossary) {
  return Object.entries(glossary).map(([k, g], i) => conceptRow(k, g, (i + 1) * 10)).join(',\n')
}
