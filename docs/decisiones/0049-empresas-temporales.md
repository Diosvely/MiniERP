# ADR 0049 · Empresas temporales: los registrados importan su diario sin llenar la base de datos

- **Fecha:** 2026-10-26
- **Versión:** v0.49.0
- **Estado:** aceptada
- **Cambia en parte:** ADR 0004 (límite de empresas) y ADR 0021 (quién importa) y ADR 0027 (quién usa la IA)

## Contexto

La base de datos gratuita de Supabase tiene **500 MB**. Por eso solo importaban diarios el owner y los miembros. Pero
importar tu propio diario y preguntarle a la IA es lo que más engancha a quien prueba el ERP. Diosvely propuso
**empresas virtuales**: que un registrado pueda importar, y que lo importado se borre cuando se vaya. El diseño se
validó antes de construir (`diseno-v0.49.0.md`).

Al revisar el código aparecieron dos cosas:
- un registrado ya podía importar, gastando su única empresa permanente (el ADR 0021 decía que importaba el owner);
- los registrados no tenían IA.

Se midió el espacio: un diario de 20.000 líneas ocupa unos 15 MB en el peor caso, contando la tabla intermedia de la
importación.

## Decisión

1. **Quién importa y cómo** (migración 0072):
   - el **owner** y los **miembros** (con perfil puesto por el owner, o titulares de los datos de una empresa)
     importan como siempre, en **permanente**;
   - un **registrado** importa **siempre en una empresa temporal**, que no gasta su empresa permanente; esa queda para
     crearla a mano o cargar un caso, y en ella no se puede importar;
   - los **invitados de la demo**, como antes: no crean nada.
2. **Cuándo se borra:** tras **2 h sin usar la aplicación** o, como muy tarde, a las **48 h**. Una temporal a la vez;
   nadie la vuelve permanente, la alarga ni la publica como demo.
3. **No se intenta saber cuándo se va el usuario**, porque el navegador no lo garantiza (móvil, batería, varias
   pestañas). En su lugar:
   - un **latido**: la web avisa «sigo aquí» cada 5 minutos;
   - una **limpieza programada** (pg_cron, cada 15 minutos) que borra por tandas las caducadas, con sus asientos;
   - al cerrar la pestaña, un aviso adelanta el borrado a unos 10 minutos (si otra pestaña sigue abierta, su latido la
     mantiene viva);
   - sin pg_cron, la limpieza se hace al empezar cada importación temporal.
4. **Topes**, en una tabla de ajustes (`erp.temp_settings`) que se cambia con un UPDATE, sin migración:
   - 20.000 líneas por importación;
   - 200.000 líneas entre todas las temporales vivas, unos 150 MB en el peor caso;
   - 25 temporales a la vez;
   - freno si la base de datos pasa de 425 MB (el 85 % de 500);
   - si se llega a uno de ellos, «ahora hay muchas empresas de prueba, prueba en un rato».
5. **IA:** el registrado la tiene en su temporal, con **5 consultas al día**; los miembros, 10; el owner, sin límite.
6. **En la web:**
   - «Prueba el ERP con tu diario» en la lista de empresas, con lo que dura y sus topes;
   - el aviso antes de subir, y el tope de líneas comprobado antes de subir;
   - «⏳ Temporal» en la lista y una franja en la empresa que dice cuándo se borra.

## Alternativas descartadas
- **Borrar al cerrar la pestaña.** El aviso de cierre no siempre llega, y con dos pestañas abiertas se borraría una
  empresa que sigue en uso. Es un «además», no lo que garantiza el borrado.
- **Un tope de 10 empresas.** Con un presupuesto de líneas caben muchas importaciones pequeñas y pocas grandes; el
  número de empresas solo es un segundo freno.
- **Dejar que el registrado elija entre permanente y temporal.** Su empresa permanente se llenaría con el primer diario
  importado y la base de datos crecería sin control.
- **Mirar solo el tamaño de la base de datos.** Postgres reutiliza el espacio de lo borrado pero no lo devuelve: el
  tamaño se queda en el pico. Por eso el tope principal son las líneas vivas.

## Consecuencias
- Cualquiera que se registre puede probar el ERP y la IA con su propio diario, y la base de datos no crece sin control.
- Más privacidad: si alguien sube datos reales, no se quedan guardados.
- **Limitaciones conocidas:**
  - la limpieza programada necesita pg_cron activado en Supabase;
  - el tamaño que enseña Supabase no baja al borrar (se reutiliza); para que baje hace falta un `VACUUM FULL`;
  - una temporal no se puede convertir en permanente: lo que se quiera guardar, a Excel;
  - el límite de 20.000 líneas deja fuera los diarios grandes; para eso están los miembros.
- **Pruebas:** 66 de 66 en la base de datos (fase 66: quién importa en temporal, caducidad, latido, limpieza, topes, IA
  y permisos) y 274 tests en la web. Comprobado en el navegador a 1366 y 1920 px (claro y oscuro) y en el móvil, sin
  errores de accesibilidad.

## Cómo explicarlo
- **Un entorno de pruebas aparte de lo real:** los ERP de verdad lo ofrecen (los entornos «sandbox» de Business Central,
  las cuentas de prueba de SAP). Aquí es lo mismo, a escala: se prueba sin tocar lo permanente.
- **No hace falta saber cuándo se va alguien:** basta con saber cuándo fue la última vez que dio señales. Es el mismo
  principio que el cierre automático de sesión de un banco.
- **Limitar por lo que de verdad ocupa:** no es lo mismo una empresa con 500 líneas que una con 20.000. Por eso el
  presupuesto se mide en líneas, y el número de empresas es solo un segundo freno.
- **Las reglas, en la base de datos:** quién importa, cuándo se borra y los topes los decide PostgreSQL. La web solo
  enseña y avisa: aunque alguien se salte la web, las reglas se cumplen.
