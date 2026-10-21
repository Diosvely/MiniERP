// Paso 218b · v0.41.2 · Tests más tolerantes en Windows: 30 s por test y la mitad de los núcleos (vite.config.js)
// Uso (desde la carpeta frontend):   node aplicar-paso218b-web.mjs
// Se puede ejecutar dos veces sin problema. Si vite.config.js no es el esperado, lo dice y no lo toca.
import fs from 'node:fs'

const OLD = "import react from '@vitejs/plugin-react'\nimport { defineConfig } from 'vite'\n\n// https://vite.dev/config/\nexport default defineConfig({\n  plugins: [react()],\n})\n"
const NEW = "import react from '@vitejs/plugin-react'\nimport { defineConfig } from 'vite'\n\n// https://vite.dev/config/\nexport default defineConfig({\n  plugins: [react()],\n  // Tests (Vitest). En Windows cada fichero de tests arranca su propio proceso (~1,5 s): con un proceso por n\u00facleo a la\n  // vez, el PC se satura y tests de milisegundos llegan a tardar m\u00e1s de 5 s (v0.41.2, visto en el PC de Diosvely).\n  // Por eso: la mitad de los n\u00facleos y 30 s de margen por test.\n  test: {\n    testTimeout: 30000,\n    maxWorkers: '50%',\n  },\n})\n"
const TEST = "import { describe, expect, it } from 'vitest'\nimport fs from 'node:fs'\nimport { fileURLToPath } from 'node:url'\n\n// Regresi\u00f3n (v0.41.2): en el PC de Diosvely, con 27 ficheros a la vez, tres tests r\u00e1pidos superaron los 5 s por\n// defecto (compare, glossary y sources) y la ejecuci\u00f3n sal\u00eda en rojo sin que hubiera ning\u00fan fallo real\ndescribe('configuraci\u00f3n de los tests', () => {\n  const cfg = fs.readFileSync(fileURLToPath(new URL('../vite.config.js', import.meta.url)), 'utf8')\n  it('margen por test de 30 s y la mitad de los n\u00facleos', () => {\n    expect(cfg).toMatch(/testTimeout: 30000/)\n    expect(cfg).toMatch(/maxWorkers: '50%'/)\n  })\n})\n"
const norm = (s) => s.replace(/\r\n/g, '\n')

if (!fs.existsSync('vite.config.js') || !fs.existsSync('src')) {
  console.error('✗ Ejecútalo desde la carpeta frontend (donde están vite.config.js y src).'); process.exit(1)
}
const actual = norm(fs.readFileSync('vite.config.js', 'utf8'))
if (actual === NEW) console.log('· vite.config.js ya estaba')
else if (actual === OLD) { fs.writeFileSync('vite.config.js', NEW); console.log('✓ vite.config.js') }
else { console.log('⚠ vite.config.js no es el esperado: no lo toco. Pásamelo y lo miro.'); process.exit(1) }
const p = 'tests/config.test.js'
if (fs.existsSync(p) && norm(fs.readFileSync(p, 'utf8')) === TEST) console.log('· ' + p + ' ya estaba')
else { fs.writeFileSync(p, TEST); console.log('✓ ' + p) }
console.log('\n✔ Paso 218b aplicado. Ahora: npm test')
