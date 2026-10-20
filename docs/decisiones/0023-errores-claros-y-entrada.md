# ADR 0023 · Errores en lenguaje claro, pantalla de entrada y plantillas de asientos

- **Fecha:** 2026-10-10
- **Versión:** v0.26.0
- **Estado:** aceptada

> Este ADR se guardó por error con el texto del Pull Request. Se rehízo con su formato el 20-10-2026 (v0.40.1), con
> el mismo contenido.

## Contexto

Son los bloques C, E y F del plan de experiencia de usuario:
- los mensajes de error de la base de datos llegaban en inglés técnico;
- la entrada a la aplicación no explicaba qué era ni destacaba la demo;
- quien empieza no sabía qué cuentas usar en un asiento.

## Decisión

1. **Errores claros:** `errors.js` (85 reglas) y `ErrorBox` dicen qué ha pasado y qué hacer. Ofrecen un botón «Ir a…»
   a la pantalla donde se arregla y, plegado, el detalle técnico. Se aplica a las 27 cajas de error.
   - Sin migraciones: los mensajes de la base de datos no cambian, se traducen en la web.
2. **Pantalla de entrada** (`Landing.jsx`):
   - propuesta de valor;
   - la demo destacada, visible sin desplazarse en 375 px;
   - pestañas con etiquetas, mostrar contraseña y confirmación por correo;
   - pie de portfolio.
3. **Asientos para principiantes:**
   - `templates.js`, con 5 plantillas;
   - buscador de cuentas por número o por nombre, manejable con el teclado;
   - explicaciones del Debe y el Haber, y de borrador frente a contabilizar.

## Consecuencias
- Las reglas se probaron contra los 151 mensajes reales de las migraciones: reconocen 113 y el resto se muestra tal cual.
- Pruebas en el navegador (Playwright): las cajas de error en español e inglés, la pantalla de entrada (9 casos) y
  las plantillas y el buscador (11 casos). CI en verde: 21 pruebas SQL, lint, build y auditoría de dependencias.
