# ADR 0025 · Seguridad: cabeceras HTTP, IA endurecida, CAPTCHA, limpieza de invitados y tests de la web

- **Fecha:** 2026-10-11
- **Versión:** v0.28.0
- **Estado:** aceptada
- **Completa a:** ADR de acceso de invitados (migración 0015), que dejaba la limpieza de invitados como tarea manual.

## Contexto

El análisis técnico del repositorio (plan de mejoras, bloques 2 a 5) señaló cinco riesgos en una app pública:
1. **Sin cabeceras de seguridad:** la web se podía meter en un `iframe` ajeno (*clickjacking*) y no había CSP.
2. **`/api/ai` y `/api/tutor`:**
   - devolvían al navegador el texto interno de PostgreSQL o del modelo (`detail`);
   - aceptaban cualquier `company_id` y cualquier tamaño de cuerpo.
3. **El enlace `?demo` creaba un usuario anónimo nada más cargar la página:** cualquier robot que lo visitara llenaba
   `auth.users`.
4. **Los invitados no se borraban nunca** (la migración 0015 solo proponía hacerlo a mano).
5. **La web no tenía tests:** la CI solo hacía lint y build.

## Decisión

1. **`frontend/public/_headers`** (Cloudflare Pages):
   - **CSP ajustada al código real**: solo `'self'`, Supabase (`https` y `wss`) y Cloudflare Turnstile;
   - `frame-ancestors 'none'` y `X-Frame-Options: DENY`, `nosniff`, `Referrer-Policy`, `Permissions-Policy`, HSTS
     y COOP;
   - comprobada sirviendo la build real: ninguna violación de la CSP.
2. **Funciones de IA endurecidas:**
   - el navegador solo recibe un **código** (`context_denied`, `ai_failed`…) y el detalle va al registro de
     Cloudflare (`console.error`);
   - `company_id` tiene que ser un **UUID** (si no, 400 sin llamar a Supabase);
   - cuerpo de la petición de **2 KB** (analista) y **4 KB** (tutor), o 413.
3. **CAPTCHA con Cloudflare Turnstile** en la demo, el registro y el inicio de sesión:
   - Supabase lo valida (*Attack Protection*);
   - `?demo` ya no crea el invitado al cargar: destaca el botón;
   - sin `VITE_TURNSTILE_SITE_KEY`, la web funciona sin CAPTCHA (desarrollo y despliegue previo).
4. **Limpieza automática de invitados** (migración `0028`):
   - `erp.cleanup_guests(7)` borra los anónimos de más de 7 días **y sus filas en `erp`** (no hay claves foráneas
     hacia `auth.users`);
   - la ejecuta `pg_cron` cada día a las 03:30 UTC;
   - sin `pg_cron`, la migración solo avisa, así que la CI sigue en verde.
5. **Tests de la web con Vitest** (47): formatos, rutas, importadores, errores claros, paridad de idiomas, glosario,
   plantillas y la defensa de las funciones. Corren en la CI en cada PR.

## Alternativas descartadas

- **CSP con `unsafe-eval` o dominios genéricos (`*`):** innecesario; el código no usa `eval` ni recursos externos.
- **Quitar `'unsafe-inline'` de `style-src`:** React usa `style={{…}}` en las barras de progreso. Es un riesgo bajo
  (estilos, no scripts) y se acepta.
- **reCAPTCHA de Google:** Turnstile es gratuito, no rastrea al usuario y casi nunca pide resolver nada.
- **Clave foránea con `on delete cascade` hacia `auth.users`:** acoplaría el esquema `erp` al de Supabase Auth. Una
  función explícita, probada y llamada desde `pg_cron` es más clara.
- **Tests de interfaz (React Testing Library) ya:** se empezó por la lógica pura, que es donde están las reglas.
  Las pantallas siguen cubiertas por Playwright en el desarrollo.

## Consecuencias

- Un robot ya no puede crear invitados en masa ni leer errores internos.
- Los invitados viejos desaparecen solos.
- La CI vigila tres capas en cada PR:
  - **22 pruebas SQL**;
  - **47 tests de la web**;
  - lint, build y auditoría de dependencias.
- **Pasos manuales en cada instalación:**
  - el widget de Turnstile y la `VITE_TURNSTILE_SITE_KEY`;
  - activar el CAPTCHA en Supabase **después** de desplegar el widget;
  - activar `pg_cron` antes de la migración 0028.
- **Pendiente:**
  - tests de componentes;
  - límite de peticiones por IP en `/api/*` (Cloudflare Rate Limiting);
  - recuperar la contraseña por correo, que tendrá que llevar el CAPTCHA.