# ADR 0053 · Tablero «Rentabilidad y márgenes»: un tablero nuevo son filas del catálogo

- **Fecha:** 2026-11-01
- **Versión:** v0.53.0
- **Estado:** aceptada

## Contexto

Con la v0.52.0 llegó el catálogo de tableros en la base de datos y un primer tablero, el «Resumen de dirección».
Diosvely pidió cinco más, «poco a poco»: rentabilidad, tesorería, impuestos, ventas y gastos, y calidad de la
contabilidad (`plan-tableros.md`). Se empieza por el más sencillo, para comprobar la promesa del ADR 0052: que un
tablero nuevo son filas, no código. El diseño se validó antes de construir.

## Decisión

1. **El tablero «Rentabilidad y márgenes», en el catálogo** (migración 0080):
   - **cifras clave:** cifra de negocios, margen bruto, EBITDA y resultado, frente al año anterior a la misma fecha;
   - **márgenes a lo largo del año** (líneas, acumulado a cada fin de mes): margen bruto, margen EBITDA y margen neto;
   - **ventas y margen bruto de cada mes** (barras);
   - **estructura de costes** (tabla): aprovisionamientos, personal, otros gastos y amortización sobre las ventas, y lo
     que queda: el margen de explotación y el neto.
2. **13 métricas nuevas que salen de la PyG del ERP, partida a partida:**
   - de la PyG: aprovisionamientos (4), personal (6), otros gastos de explotación (7), amortización (8) y resultado de
     explotación (A);
   - calculadas a partir de ellas: margen bruto = ventas − aprovisionamientos; EBITDA = resultado de explotación +
     amortización, la misma fórmula que en Ratios; y los márgenes y pesos sobre las ventas.
3. **Signo en las métricas de partida.** En la PyG los gastos son negativos porque se restan. En un tablero se leen mejor
   en positivo («aprovisionamientos 37.000 €»), así que una métrica de partida puede llevar `sign = -1`, como ya podían
   las de grupo. Una suma, una resta o un cociente no llevan signo (lo impide la base de datos).
4. **Web: ejes en % y tercera serie.** El eje de un gráfico de márgenes se redondea en % (0 %, 50 %, 100 %); antes
   salía en unidades y los márgenes, que valen entre 0 y 1, quedaban aplastados contra el cero. Hay un tercer color de
   serie (magenta) y, cuando un gráfico tiene varias series, el año anterior va discontinuo en el color de cada una;
   con una sola, sigue en gris. «Tableros ▾» lee el catálogo, así que el tablero aparece solo.

## Alternativas descartadas
- **Métricas de gasto como «grupo de cuentas»** (60, 64, 62…). Darían cifras parecidas, pero no las mismas que la PyG:
  la partida 4 incluye la variación de existencias (61) y los trabajos de otras empresas, y la 7 no es todo el grupo 62.
  Con las partidas, el tablero dice exactamente lo mismo que la PyG.
- **Restar en la web** (o en métricas «diferencia» con cero). Funcionaría, pero repartiría la regla «los gastos en
  positivo» entre la base de datos y la web.
- **Un gráfico de márgenes con eje fijo de 0 a 100 %.** Simple, pero con márgenes negativos (pérdidas) o pequeños el
  gráfico no enseñaría nada.

## Consecuencias
- **Un tablero nuevo son filas:** la v0.53.0 solo programa el signo (una línea) y el eje en %. Los siguientes tableros
  reutilizan las métricas nuevas.
- **El tablero y la PyG dicen lo mismo.** Con el caso completo: margen bruto 83.000 € (120.000 − 37.000), EBITDA
  79.360 € (76.360 + 3.000).
- **Limitaciones conocidas:**
  - la zona de referencia de los márgenes está vacía: Ratios no la tiene (dependen del sector);
  - cuando los márgenes casi coinciden (sin amortización ni impuesto), las líneas se solapan; «Ver como tabla» enseña
    los números.
- **Pruebas:** 74 de 74 en la base de datos y 290 tests de la web. La fase 74 comprueba con el caso completo:
  - que los gastos salen en positivo (regresión: sin el signo, «aprovisionamientos −37.000»);
  - que las cifras y las series cuadran con la PyG en los 12 fines de mes, y el EBITDA, el margen de explotación y el
    neto con la pantalla Ratios;
  - que ventas − costes + el resto de partidas de explotación = resultado de explotación (no queda nada fuera);
  - «hasta» con el año anterior, la simulación con un borrador y que otra empresa no ve nada;
  - 44 ms con una empresa de 30.000 asientos al lado.

## Cómo explicarlo
- **Margen bruto:** de cada euro vendido, lo que queda después de pagar lo vendido (aprovisionamientos, con la
  variación de existencias). Mide el negocio en sí: precio frente a coste.
- **EBITDA:** el resultado de explotación antes de amortizar. Sirve para comparar empresas con más o menos
  inmovilizado, pero **no es caja**: no recoge cobros ni pagos pendientes, ni las inversiones.
- **Margen de explotación frente a margen neto:** la diferencia son los intereses y el impuesto sobre beneficios; si el
  neto cae mucho más que el de explotación, el problema es la financiación o la fiscalidad, no el negocio.
- **Estructura de costes:** cada gasto sobre las ventas. Con los pesos y el margen de explotación se ve en qué se va
  cada euro vendido.
- **Signo:** la PyG del PGC presenta los gastos en negativo porque es una suma; un tablero los enseña en positivo
  porque se leen como «cuánto se gasta». Es la misma cifra cambiada de signo, en un solo sitio (el catálogo).
- **En BC y SAP:** Business Central calcula estos márgenes con los *Account Schedules* (esquemas de cuentas) y los
  enseña en gráficos del *Role Center*; en SAP S/4HANA, la *Fiori app* «Margin Analysis» y las *KPI tiles* de
  rentabilidad. *(Pendiente de validar por Diosvely.)*
