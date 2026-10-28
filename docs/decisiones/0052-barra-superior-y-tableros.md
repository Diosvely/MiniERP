# ADR 0052 · Barra superior y tableros: el catálogo en la base de datos, el dibujo en la web

- **Fecha:** 2026-10-28
- **Versión:** v0.52.0
- **Estado:** aceptada

## Contexto

Diosvely quería tableros **dentro del propio ERP**, con la idea de «las reglas en la base de datos y el tablero en la
web»: lo mismo que se hizo para Power BI en la v0.50.0, pero sin salir del ERP. También quería una **barra arriba**
(«como Microsoft»), encima del contenido, que empezara solo con «Tableros» y fuera creciendo poco a poco. El diseño se
validó antes de construir (`diseno-v0.52.0.md`).

## Decisión

1. **Una barra superior** encima del contenido de la empresa, en todas sus pantallas. De momento, un solo botón,
   «Tableros ▾», que despliega los tableros del catálogo. Cada tablero tiene su dirección
   (`#/empresa/<id>/tableros/<código>`). El menú lateral no cambia.
2. **El catálogo, en la base de datos** (decisión de Diosvely; migración 0075): tres tablas de solo lectura para la web.
   - `erp.dash_metrics`: una métrica es una partida del Balance o de la PyG, un grupo de cuentas de la PyG, o una suma,
     resta o cociente de otras métricas, con su unidad y la zona de referencia de los Ratios.
   - `erp.dashboards` y `erp.dash_widgets`: los tableros y sus tarjetas (cifras, barras, líneas o tabla).
   - Un tablero nuevo son filas, no código. Más adelante, la IA podrá proponer tableros a partir del catálogo.
3. **Las métricas no repiten reglas:** salen de las mismas funciones que el Balance y la PyG. Cuadran al céntimo con
   ellos, también con la simulación de los asientos en edición (v0.51.0).
4. **Una sola llamada**, `erp.dashboard_data`: cada cifra a la fecha elegida y a la misma fecha del año anterior, y las
   series de cada fin de mes de los dos ejercicios (con «lo de cada mes» ya calculado para las barras).
5. **Una pasada por el diario para todas las fechas.** El tablero necesita el balance y la PyG a 26 fechas. Llamar 26
   veces a la clasificación de siempre tardaba 18 s con 60.000 asientos. `erp.fs_classified_at` clasifica las cuentas
   a varias fechas de una vez. `erp.fs_classified_accounts` y `erp.fs_amounts` pasan a ser el caso de una fecha, con la
   misma firma y el mismo resultado, así que la regla sigue en un solo sitio: 2,6 s.
6. **Primer tablero, «Resumen de dirección»** (decisión de Diosvely): cifra de negocios, resultado, tesorería y fondo de
   maniobra; ingresos y gastos de cada mes; resultado acumulado y tesorería a fin de mes frente al año anterior; y
   liquidez, endeudamiento y margen neto con su zona de referencia.
7. **Los mismos filtros que los informes** (decisión de Diosvely): ejercicio, «hasta» con la fecha rápida y los meses,
   y la simulación. Gráficos en SVG hechos a mano, como los de Inicio, con «Ver como tabla», Excel e Imprimir.

## Alternativas descartadas
- **Tableros fijos en la web.** Más rápidos de hacer, pero cada tablero nuevo sería código nuevo, y la IA no podría
  proponerlos.
- **Una librería de gráficos.** Añade peso y dependencias para cuatro tipos de gráfico; los de Inicio ya están hechos a
  mano y se ven igual en claro, en oscuro y en el móvil.
- **Calcular las cifras en la web.** Repetiría las reglas del ERP y acabarían diciendo cosas distintas que el Balance.
- **Llamar a los informes de siempre una vez por fecha.** Correcto, pero 18 s con un diario grande.
- **Meter los tableros en el menú lateral.** Diosvely quería la barra arriba, preparada para crecer.

## Consecuencias
- El tablero y los informes dicen lo mismo, porque salen de las mismas reglas. La prueba lo comprueba en los 12 fines de
  mes.
- **Escalable:** los tableros de tesorería y cobros, rentabilidad y ventas y gastos serán filas nuevas del catálogo (y
  alguna métrica nueva).
- **Limitaciones conocidas:**
  - con 60.000 asientos el tablero tarda unos 2,6 s; la mayor parte es la seguridad fila a fila de Supabase, que ya
    pesaba en el Balance (1 s con esos datos);
  - las barras enseñan solo el ejercicio elegido; el año anterior está en «Ver como tabla» y en el Excel;
  - el catálogo lo rellenan las migraciones; no hay todavía pantalla para editarlo.
- **Pruebas:** 69 de 69 en la base de datos y 289 tests de la web. La fase 69 comprueba, con el caso completo:
  - que las cifras clave coinciden con la PyG y el Balance, y la liquidez, el endeudamiento y el margen con la pantalla
    Ratios;
  - que el resultado y la tesorería coinciden en los 12 fines de mes, y que los ingresos y gastos de cada mes,
    acumulados, dan el resultado;
  - que el año anterior se compara a la misma fecha, y que la simulación da lo mismo que contabilizar;
  - que el catálogo está completo, que la web solo lo lee y que otra empresa no ve nada.

## Cómo explicarlo
- **El catálogo es una pequeña «capa semántica»:** dice qué es cada cifra (de qué partida sale y cómo se calcula) una
  sola vez. La web, Power BI o la IA la leen; ninguno la repite.
- **Separar el qué del cómo:** la base de datos decide qué se enseña (tarjetas y métricas) y cuánto vale; la web solo
  decide cómo se dibuja.
- **Una pasada en vez de 26:** es lo mismo que haría un contable con el mayor: sumar por días una vez y leer el saldo a
  cada fecha, en lugar de volver a sumar todo el diario para cada fin de mes.
- **Nunca solo color:** cada variación lleva ▲ ▼ y su porcentaje, y cada gráfico se puede leer como tabla.
- **En BC y SAP:** Business Central tiene los *Role Centers* con sus *cues* y gráficos; SAP, las *Overview Pages* de
  Fiori y las *KPI tiles*, que leen *CDS views*. Aquí, el catálogo y `erp.dashboard_data`. *(Pendiente de validar por
  Diosvely.)*
