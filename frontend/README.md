# Mini ERP · web (React + Vite)

La web del Mini ERP: dibuja lo que decide la base de datos (Supabase, schema `erp`). Las reglas contables no están
aquí, sino en `database/` (ver el [README principal](../README.md) y el [modelo de datos](../docs/modelo-datos.md)).

## Comandos
```bash
npm ci          # instalar las dependencias
npm run dev     # web en http://localhost:5173 (necesita .env.local con VITE_SUPABASE_URL y VITE_SUPABASE_KEY)
npm test        # tests con Vitest (tests/)
npm run lint    # ESLint
npm run build   # versión para Cloudflare Pages (dist/)
```
Las variables de ejemplo están en `.env.example`. Solo la clave **publicable** de Supabase; nunca la secreta.

## Dónde está cada cosa
- `src/components/`: una pantalla o pieza por fichero (Inicio, Asientos, Facturas, Balance, Tableros…).
- `src/*.js`: la lógica pura de cada pantalla, que es lo que prueban los tests (`dashboards.js`, `reportPeriod.js`,
  `anomalies.js`, `importers.js`, `format.js`…).
- `src/i18n/`: los textos en español (`es.js`) e inglés (`en.js`), con las mismas claves.
- `functions/api/`: Pages Functions de Cloudflare para la IA (`ai.js`, el Analista, y `tutor.js`, el Tutor).
- `public/_headers`: cabeceras de seguridad (CSP…) que aplica Cloudflare Pages.
- `tests/`: tests de Vitest; cada arreglo lleva el suyo, que falla sin el arreglo (regla A1).

## Gráficos
Los gráficos (Inicio, informes y tableros) están dibujados a mano en SVG, sin librerías: cada serie lleva su nombre en
la leyenda, se pueden ver como tabla y funcionan en claro, en oscuro y en el móvil.
