import js from '@eslint/js'
import globals from 'globals'
import reactHooks from 'eslint-plugin-react-hooks'
import reactRefresh from 'eslint-plugin-react-refresh'
import { defineConfig, globalIgnores } from 'eslint/config'

export default defineConfig([
  globalIgnores(['dist']),
  {
    files: ['**/*.{js,jsx}'],
    extends: [
      js.configs.recommended,
      reactHooks.configs.flat.recommended,
      reactRefresh.configs.vite,
    ],
    languageOptions: {
      globals: globals.browser,
      parserOptions: { ecmaFeatures: { jsx: true } },
    },
    rules: {
      // Regla nueva de React 19: carga de datos en useEffect. Funciona; se refactoriza por pantallas (v0.25+)
      'react-hooks/set-state-in-effect': 'warn',
      // El proveedor de idioma exporta también su hook useI18n (patrón habitual)
      'react-refresh/only-export-components': ['warn', { allowExportNames: ['useI18n'] }],
    },
  },
])