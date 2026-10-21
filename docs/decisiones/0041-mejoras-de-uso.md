# ADR 0041 · Mejoras de uso: pantalla ancha, menú en acordeón, asientos en una línea y panel de IA

- **Fecha:** 2026-10-21
- **Versión:** v0.41.1 y v0.41.2
- **Estado:** aceptada

## Contexto

Al empezar a contabilizar de verdad con el ERP, y con ContaSol abierto al lado, aparecieron cuatro problemas de uso:

1. **En el PC la pantalla parecía un móvil gigante.** El contenido medía 1.120 px como máximo, con letra de 16 px y
   mucho relleno, así que había que hacer mucho scroll.
2. **El menú de la izquierda crecía con cada módulo.** En modo Auditor ya era más largo que muchas pantallas.
3. **Meter asientos era lento:** cuenta, Debe y Haber en dos filas, y un botón «=» y una «✕» por línea.
4. **La IA estaba repartida.** El Tutor ocupaba la parte de arriba de Nuevo asiento y el Analista estaba al final del
   EFE y de los Ratios.

Las cuatro mejoras se anotan en un documento privado del proyecto (`mejoras-de-uso.md`) y se meten entre versiones.

## Decisión

1. **Pantalla ancha** (`src/wideLayout.js`, CSS):
   - en el PC el contenido llega a 1.600 px de ancho;
   - desde 1.320 px, dos tarjetas seguidas sin tabla van una al lado de la otra. Una tarjeta sin pareja ocupa todo
     el ancho, para no dejar un hueco al lado;
   - en el PC (desde 900 px) la letra baja a 14 px y se reduce el relleno; el móvil no cambia;
   - en Cierre del ejercicio, el asistente queda a la izquierda y el cierre a la derecha.
2. **Menú en acordeón** (`src/menuAccordion.js`):
   - en modo Auditor se ven solo los títulos de las áreas y hay una sola abierta: la de la pantalla actual;
   - las flechas ↑ ↓ recorren el menú;
   - «Publicar como demo» y «Borrar empresa» pasan a un área «Empresa», plegada.
3. **Asientos en una línea** (`src/entryKeys.js`):
   - cada línea del asiento es una fila: Cuenta | Debe | Haber;
   - Enter avanza y, al final de la última línea, crea otra;
   - lo que falta para cuadrar sale en gris en el lado que toca, y Enter o «=» lo ponen;
   - Enter en una línea vacía con el asiento cuadrado lleva a «Contabilizar»;
   - la línea se borra con Ctrl + Supr o con la papelera que aparece al pasar el ratón.
4. **Panel de IA** (`src/aiPanel.js`, `AiPanel`, `aiContext`):
   - un botón «✨ IA» abajo a la derecha abre un panel lateral con dos pestañas, Tutor y Analista;
   - el Tutor es una conversación, y «Pasar al asiento» lleva la propuesta a Nuevo asiento desde cualquier pantalla;
   - el Analista interpreta el ejercicio que la pantalla le pasa (EFE, Ratios);
   - en el PC ancho el panel se pone al lado del contenido; en el móvil ocupa toda la pantalla;
   - la conversación no se guarda en la base de datos, porque puede llevar nombres de terceros.
5. **Calidad:**
   - cada comportamiento tiene tests de la lógica, sin React;
   - pasa axe-core (WCAG 2 A/AA) en modo claro y oscuro, a 1.366 px, a 1.920 px y en el móvil;
   - cada arreglo lleva su prueba de regresión.

## Alternativas descartadas
- **Cinta tipo Word / Excel**, con pestañas arriba como BC o ContaSol. Aprovecha mejor el ancho, pero es un rediseño
  de la cabecera, del móvil y de todas las pantallas. Primero se prueba el acordeón unos días; la cinta queda apuntada.
- **Emparejar las tarjetas solo con CSS.** `:has()` no se puede anidar, así que el CSS no puede preguntar si la
  tarjeta siguiente también es pequeña. Lo resuelven unas líneas de JavaScript que solo ponen una clase.
- **El cursor directamente al Haber cuando lo que falta va al Haber.** La 472 de una compra va al Debe aunque el
  asiento aún no cuadre. Por eso el cursor va siempre al Debe, y un Enter en el Debe vacío salta al Haber.
- **Guardar la conversación del Tutor** en la base de datos o en el navegador. Puede llevar nombres de terceros, y el
  modelo de privacidad (ADR 0027) solo manda a la IA cifras y lo que tú escribes en ese momento.
- **Un chat libre con los datos** («¿quién me debe más?»). Sin el catálogo de métricas y de herramientas, la IA
  tendría que calcular, y en este ERP la IA consulta, nunca calcula. Queda para la fase 2.

## Consecuencias
- Menos scroll: entre un 10 % y un 20 % menos de alto en las pantallas largas, y en Cierre, un 30 %.
- Un asiento de tres líneas se mete solo con el teclado.
- **Arreglos que salieron por el camino:**
  - en el móvil, Clientes y proveedores se salía 90 px de la pantalla;
  - en modo Auditor quedaba un hueco gris bajo la ruta;
  - faltaba el nombre del módulo Nóminas en el aviso de cuentas controladas;
  - tres etiquetas no tenían contraste suficiente;
  - en Windows, los tests superaban los 5 s por saturación.
- **Pruebas:** 187 tests de la web, 28 de ellos nuevos (pantalla ancha, menú, teclado, panel y configuración).

## Cómo explicarlo
- **Un ERP se mide también por las pulsaciones.** Un contable mete cientos de asientos al mes, así que cada clic que
  se ahorra cuenta. Por eso los programas españoles (ContaSol, A3, Sage) hacen avanzar con Enter y proponen el
  importe que falta para cuadrar.
- **El importe que falta se calcula, no se adivina.** Es Debe − Haber de las demás líneas, en céntimos para no
  arrastrar decimales. Si lo que falta va al Haber, se propone en el Haber.
- **El Debe es el primer sitio por defecto, no el lado que «toca».** El ERP no sabe si la línea siguiente es otro
  cargo (el IVA) o el abono que cuadra. Proponer es ayudar; decidir por ti sería un error.
- **La IA a un lado, no encima.** El Tutor propone y el formulario decide: la propuesta solo llega a Nuevo asiento
  cuando pulsas «Pasar al asiento», y nada se contabiliza sin revisarlo. En BC el equivalente es Copilot en un panel
  lateral, y en SAP, Joule.
