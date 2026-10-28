# ADR 0051 · Mes rápido y simulación con los asientos en edición en los informes

- **Fecha:** 2026-10-28
- **Versión:** v0.51.0
- **Estado:** aceptada

## Contexto

Diosvely pidió dos mejoras de uso en los informes (diseño validado antes de construir, `diseno-v0.51.0.md`):
1. **Elegir el periodo más rápido.** El «hasta» era el calendario del navegador. En los asientos ya se escribe la fecha
   como en ContaSol (`0102`, `h`…), y a menudo lo que se quiere es «hasta fin de marzo».
2. **Ver el efecto de un asiento antes de contabilizarlo.** Es para aprender: preparar un asiento, mirar cómo cambian
   el balance, la PyG o los ratios y, si convence, contabilizarlo; si no, borrarlo.

## Decisión

1. **Mes rápido** (solo web) en Balance, PyG, Sumas y saldos, Libro mayor y Comprobaciones:
   - el «hasta» es el campo de fecha rápida de Nuevo asiento; `2` o `0102` se leen en el ejercicio elegido;
   - una fila de botones «Todo · Ene … Dic»: un mes pone «hasta» en su último día; «Todo», el ejercicio entero. Se
     marca el mes de la fecha, también si se escribe a mano;
   - al cambiar de ejercicio, el «hasta» pasa al mismo mes del nuevo (un fin de mes sigue siendo fin de mes).
2. **Simulación** con una casilla, «Incluir los asientos en edición (simulación)», en Balance, PyG, Sumas y saldos,
   Libro mayor, Estado de flujos y Ratios. Marcada, una franja dice cuántos asientos entran y lleva a «Asientos»; el
   Excel y la impresión llevan «SIMULACIÓN» en el título.
3. **Solo los «en edición»** (decisión de Diosvely): los borradores que cuadran y se podrían contabilizar, el mismo
   cálculo que el estado de la pantalla «Asientos» (`erp.draft_problem`). Los «con error» nunca: descuadrarían el
   balance.
4. **Una sola regla en la base de datos** (migración 0074): `erp.counts_in_reports` dice si un asiento cuenta en los
   informes. Las funciones de base (clasificación del balance y la PyG, sumas y saldos, mayor y flujos) la usan en
   lugar de «solo contabilizados».
5. **La simulación la enciende solo la web**, con un parámetro nuevo, `p_drafts` (por defecto «no»), en las funciones
   que llama. Cada una la enciende para su consulta (un ajuste local de la transacción, `erp.simulate`) y la deja como
   estaba. Todo lo demás llama a las mismas funciones sin el parámetro y sigue viendo solo lo contabilizado: el cierre
   del ejercicio y del mes, las liquidaciones, los modelos, el impuesto sobre sociedades, las comprobaciones, el
   contexto de la IA, el caso completo y el puente a Power BI.
6. **El Libro diario no se simula:** es el libro legal y solo lleva lo contabilizado.
7. **Seguridad:** `erp.draft_problem` sigue cerrada a la web (contesta de cualquier asiento). La regla usa
   `erp.draft_ready`, que solo contesta de las empresas que el usuario puede leer.

## Alternativas descartadas
- **Pedir la simulación con una cabecera HTTP.** Era lo previsto en el diseño, pero Supabase podría rechazar una
  cabecera propia por CORS, y la web dependería de algo que no se ve en la llamada. El parámetro se ve, se prueba y
  documenta la API.
- **Funciones duplicadas «con borradores».** Dos versiones de cada informe acabarían diciendo cosas distintas. Con una
  sola regla, la simulación y el informe normal salen del mismo código.
- **Incluir también los borradores «con error».** El balance podría descuadrar y confundir justo a quien aprende.
- **Simular en el Libro diario.** Rompería la idea de libro legal; los borradores ya se ven en «Asientos».

## Consecuencias
- Se ve el efecto de un asiento antes de contabilizarlo, en los mismos informes de siempre.
- La web actual seguía funcionando con la 0074 aplicada: el parámetro es opcional.
- **Rendimiento:** con 60.000 asientos, el mayor de una cuenta pasa de unos 0,1 s a unos 0,2 s.
- **Limitaciones conocidas:**
  - la franja de Flujos y Ratios cuenta los borradores del ejercicio elegido; la columna del anterior también los
    incluye si los hay;
  - en el mayor, un asiento en edición no tiene número (sale con ✎) y no enlaza a su ficha.
- **Pruebas:** 68 de 68 en la base de datos y 281 tests de la web. La fase 68 comprueba:
  - que sin simulación nada cambia aunque haya borradores;
  - que con simulación los informes son exactamente los de después de contabilizar el borrador, y el que no cuadra no
    entra;
  - que la simulación se apaga al terminar cada informe y que el cierre y las comprobaciones no la ven;
  - que no se puede preguntar por los borradores de otra empresa, y los permisos y firmas.

## Cómo explicarlo
- **Una sola regla, muchos consumidores:** «qué cuenta en un informe» se decide en un único sitio. Si mañana cambia, cambia
  en todos los informes a la vez.
- **Un interruptor con alcance limitado:** la simulación vale solo para la consulta que la pide, como una variable local.
  Por eso el cierre o Power BI no pueden ver borradores por accidente.
- **Simular antes de registrar:** es lo que hace un contable con un asiento dudoso antes de contabilizarlo. Aquí se ve el
  efecto en el balance y los ratios, no solo en el asiento.
- **Prueba de que la simulación dice la verdad:** el test compara el informe simulado con el que sale después de
  contabilizar de verdad. Tienen que ser iguales.
- **En BC y SAP:** Business Central tiene la *vista previa de registro* (*Preview Posting*) y el informe de prueba del
  diario; SAP permite *simular* un documento y dejarlo *aparcado* antes de contabilizarlo. Aquí, además, se ve el
  efecto en los estados financieros. *(Pendiente de validar por Diosvely.)*
