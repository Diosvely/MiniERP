# ADR 0026 · Rendimiento con muchos datos, borrar empresas, fecha de trabajo y rastro contable

- **Fecha:** 2026-10-11
- **Versión:** v0.29.0
- **Estado:** aceptada
- **Completa a:** ADR 0002 (asientos), por el borrado de empresas y la vista `v_general_ledger`.

## Contexto

Al usar el ERP con una contabilidad real importada (de 2019 a 2024, decenas de miles de apuntes) aparecieron cinco
problemas que con pocos datos no se veían:
1. **El libro mayor no cargaba nunca:** *"canceling statement due to statement timeout"*. La vista `v_general_ledger`
   calcula el saldo acumulado con una función de ventana sobre **todos** los apuntes visibles y solo después filtra
   por cuenta. Supabase corta las consultas de la web a los ~8 s.
2. **Supabase devuelve como máximo 1.000 filas por consulta, sin avisar:** el diario, el mayor de cuentas con mucho
   movimiento y el plan de cuentas se cortaban, y los totales salían mal.
3. **No se podía borrar una empresa desde la web.** Hacía falta para enseñar una importación y después quitarla.
   Además, en local, borrar 60.000 asientos tardaba **148 s**: a 27 claves foráneas les faltaba índice.
4. **Todas las fechas por defecto eran las de hoy:** una empresa de 2019-2024 se abría en un 2026 vacío.
5. **No se podía seguir el rastro contable:** desde el mayor no había forma de ver el asiento completo.

## Decisión

1. **`erp.general_ledger(empresa, año, cuenta, hasta)`** (migración 0029):
   - **primero filtra** (índice por cuenta) y **después** calcula el saldo, como el FBL3N de SAP o los movimientos de
     una cuenta en Business Central;
   - es `security invoker`, así que RLS sigue decidiendo quién ve qué;
   - en 120.000 apuntes tarda 0,2 s, frente a 6,9 s de la vista. La vista se mantiene para el SQL Editor.
2. **Índices en todas las claves foráneas** de datos de empresa (el aviso *"unindexed foreign keys"* del Advisor de
   Supabase). Una prueba los vigila: si una clave foránea nueva nace sin índice, la CI falla.
3. **Lecturas por páginas (`src/paging.js`):** `fetchAll()` pide de 1.000 en 1.000 hasta el final. Si una página
   falla, devuelve el error, no media lista.
4. **Borrar la empresa por tandas:**
   - `erp.delete_company_step(empresa)` borra 5.000 asientos por llamada (unos 0,5 s) y devuelve cuántos quedan; la
     web repite con una barra de progreso, como la importación mes a mes. No se puede subir el límite de 8 s desde
     una función (se comprobó), así que el trabajo se divide;
   - un asiento y su contraasiento se apuntan entre sí: van siempre en la misma tanda;
   - solo el **admin de la empresa**; nunca una demo publicada (primero se despublica). Para confirmar hay que
     escribir el nombre, como la *Danger zone* de GitHub;
   - el límite de empresas cuenta las que existen: al borrar se libera la plaza.
5. **Fecha de trabajo por empresa (`src/workDate.js`)**, la *Work Date* de Business Central:
   - hoy si la empresa tiene un ejercicio abierto que incluye hoy;
   - si no, la del **último asiento contabilizado** (empresas importadas o históricas);
   - de ella salen el año de los informes, el trimestre de las liquidaciones, el "Desde" del diario (día 1 del mes)
     y la fecha de los asientos y facturas nuevos;
   - se calcula en la web (dos consultas ligeras), sin migración.
6. **Rastro contable:**
   - el nº de asiento del mayor abre la **ficha del asiento** (`#/empresa/<id>/asiento/<año>/<nº>`), identificado por
     ejercicio y número, como un documento de SAP (sociedad + nº + ejercicio);
   - cada cuenta de la ficha y del diario lleva a **su libro mayor** (`…/reports/mayor/<cuenta>/<año>`), y una
     anulación lleva a su pareja;
   - la dirección sigue a lo que se ve, así que "Volver" y el botón atrás del navegador deshacen el camino.
7. **Errores:** *statement timeout* se explica en lenguaje claro ("La consulta ha tardado demasiado").

## Alternativas descartadas

- **Subir el `statement_timeout`** del rol `authenticated`: oculta el problema, sigue fallando con más datos y deja
  la puerta abierta a consultas que bloquean la base de datos.
- **Cambiar la vista del mayor por una vista materializada:** habría que refrescarla en cada asiento. La función es
  más simple y siempre está al día.
- **Borrado en segundo plano con `pg_cron`:** más piezas y sin progreso visible. Las tandas desde la web son igual de
  seguras y se entienden mejor.
- **Fecha de trabajo guardada por usuario** (como BC): útil, pero más estado que mantener. Si hace falta, se añadirá
  un selector encima del cálculo automático.
- **Restringir la importación al propietario:** se mantiene para los Miembros, dentro de su límite, para que vean
  cómo funciona; ahora pueden borrar la empresa después.

## Consecuencias

- El ERP funciona con contabilidades reales de varios años sin cortes ni totales incompletos.
- Toda pantalla nueva que lea listas largas debe usar `fetchAll`, y toda clave foránea nueva necesita su índice (lo
  vigila la prueba de la fase 23).
- La ficha del asiento abre la puerta a navegar desde una factura o una liquidación a su asiento.
- **Pendiente:** en local con el CAPTCHA activado, `.env.local` necesita `VITE_TURNSTILE_SITE_KEY` y el widget de
  Turnstile debe aceptar `localhost`.