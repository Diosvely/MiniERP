import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  // Tests (Vitest). En Windows cada fichero de tests arranca su propio proceso (~1,5 s): con un proceso por núcleo a la
  // vez, el PC se satura y tests de milisegundos llegan a tardar más de 5 s (v0.41.2, visto en el PC de Diosvely).
  // Por eso: la mitad de los núcleos y 30 s de margen por test.
  test: {
    testTimeout: 30000,
    maxWorkers: '50%',
  },
})
