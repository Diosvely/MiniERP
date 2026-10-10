TÍTULO:
feat: v0.26.0 · errores en lenguaje claro, pantalla de entrada y plantillas de asientos

DESCRIPCIÓN:
## Qué incluye
Bloques C, E y F del plan de experiencia de usuario.

| Bloque | Qué hace |
|---|---|
| **Errores claros** | `errors.js` (85 reglas) + `ErrorBox`: qué ha pasado, qué hacer, botón "Ir a…" y detalle técnico; aplicado a las 27 cajas de error |
| **Pantalla de entrada** | `Landing.jsx`: propuesta de valor, demo destacada (visible sin scroll en 375 px), pestañas con etiquetas, mostrar contraseña, confirmación por correo, pie de portfolio |
| **Asientos para principiantes** | `templates.js` (5 plantillas), buscador de cuentas por número o nombre con teclado, explicaciones de Debe/Haber y borrador/contabilizar |

## Cambios técnicos
- Nuevos: `src/errors.js`, `src/templates.js`, `components/ErrorBox.jsx` y `components/Landing.jsx`.
- `App.jsx`: el `Login` antiguo se sustituye por `Landing`.
- `JournalEntryForm.jsx`: plantillas, combobox de cuentas propio (sin `datalist`) y explicaciones.
- Sin migraciones: los mensajes de la base de datos no cambian; se traducen en la web.
- Docs: ADR 0023, bitácora, CHANGELOG y README.

## Cómo se ha probado
- Las reglas, contra los 151 mensajes reales de las migraciones: reconoce 113; el resto se muestra tal cual.
- Playwright:
  - cajas de error en español y en inglés;
  - pantalla de entrada (9 casos: 375 px, etiquetas, contraseña mal, mostrar, requisito, registro, demo);
  - plantillas y buscador (11 casos: compra cuadrada con "=", nómina con subcuenta que falta, búsqueda sin acentos,
    ↑ ↓ Enter Escape, atajo del punto).
- CI en verde: 21 pruebas SQL, lint, build y audit.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01HyZiRWb4vTAZGnXD6A391g