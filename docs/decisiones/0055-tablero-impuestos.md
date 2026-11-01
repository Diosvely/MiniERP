# ADR 0055 · Tablero «Impuestos»: la misma regla que la liquidación, a cualquier fecha y por trimestres

- **Fecha:** 2026-11-01
- **Versión:** v0.55.0
- **Estado:** aceptada

## Contexto

Tercero de los cinco tableros nuevos (`plan-tableros.md`). Tiene que responder a: ¿cuánto IVA / IGIC he devengado y
deducido este año, cuánto toca ingresar cada trimestre y cuánto he retenido? La condición es que **cuadre con la
liquidación del ERP**, trimestre a trimestre. El diseño se validó antes de construir (`diseno-v0.55.0.md`), con tres
decisiones de Diosvely:
- el tablero enseña el **impuesto del territorio** de la empresa;
- el **estado de cada liquidación** va en la v0.57.0 (Calidad de la contabilidad);
- la lista de cuentas de impuesto pasa a una **función compartida**.

## Decisión

1. **Una sola regla para las cuentas de impuesto** (migración 0082). La lista que estaba dentro de
   `erp.tax_settlement_calc` pasa a `erp.tax_accounts(empresa, tipo)`:
   - las cuentas configuradas en Impuestos (repercutido, soportado y recargo de equivalencia);
   - y las 472 / 477 sin configurar, que cuentan en el impuesto del territorio.

   Se sacó con un script, copiando el bloque tal cual. La liquidación calcula lo mismo, y el tablero lee la misma lista,
   así que no pueden decir cosas distintas.
2. **Tipo de métrica «impuesto»** (`kind = 'tax'`, `flow = 'output' | 'input'`): devengado o deducible desde el 1 de
   enero hasta la fecha, sin los asientos de liquidación ni los del cierre y la apertura (`erp.is_settlement_entry`),
   como la liquidación.
   - `erp.tax_moves_at` lee primero los apuntes de las cuentas de impuesto (pocos, por su índice) y solo comprueba esos
     asientos.
   - El impuesto es el del territorio (`erp.company_tax_type`): IGIC en Canarias, IVA en el resto.
3. **Tipo de métrica «movimiento de cuenta»** (`kind = 'move'`, una cuenta y `flow = 'debit' | 'credit'`): lo cargado o
   abonado en el año, sin la apertura ni el cierre.
   - Los abonos de la 4751 son las retenciones practicadas, a ingresar con los modelos 111, 115 y 123.
   - Los cargos de la 473 son las soportadas, a cuenta del Impuesto sobre Sociedades.
4. **Series por trimestre** (`mode = 'quarter'`, solo en barras): lo de cada trimestre natural es el acumulado a fin de
   trimestre menos el del anterior (`erp.dash_quarters`). Con «hasta» a mitad de trimestre, ese trimestre llega hasta la
   fecha.
5. **El tablero**, con 6 métricas y 5 tarjetas:
   - cifras clave;
   - devengado y deducible de cada trimestre;
   - resultado de cada trimestre;
   - retenciones de cada trimestre;
   - resumen del año.
6. **Web:**
   - el eje con 1T a 4T, también en la tabla y el Excel;
   - el impuesto de la empresa bajo la descripción;
   - los enlaces a Liquidación y Retenciones;
   - la tabla de una tarjeta enlaza a la pantalla de sus métricas, y la columna de zona solo sale si hay zona.

## Alternativas descartadas
- **Leer el libro registro de facturas.** Es lo que da las casillas del modelo, pero el resultado de la liquidación sale
  de la contabilidad. Si el tablero leyera las facturas, podría no cuadrar con la liquidación cuando haya un apunte
  manual en una 477.
- **Copiar la lista de cuentas en el tablero.** Más rápido, pero el día que la liquidación cambie su regla, el tablero
  se quedaría atrás sin que nada avisara.
- **Llamar a la liquidación una vez por trimestre.** Correcto al cierre, pero no sirve para una fecha a mitad de
  trimestre ni para el acumulado.
- **El estado de cada liquidación aquí.** Es una cuestión de «¿me falta algo?»: va con los meses sin cerrar en Calidad
  de la contabilidad (v0.57.0).

## Consecuencias
- **Cuadra con la liquidación por construcción.** En el caso (IGIC) los resultados son 938, 308, 658 y 308 €: 8.400 €
  devengados, 6.188 € deducibles, 2.212 € de resultado y 360 € de retenciones en el año.
- **Fallo encontrado y arreglado al construir.** La restricción `flow in (…)` con el sentido vacío daba NULL, y una
  restricción que da NULL se da por buena. La fase 75 lo detectó, y ahora se exige `flow is not null`, con su regresión
  en la fase 76.
- **Limitaciones conocidas:**
  - el tipo medio repercutido incluye las autorrepercusiones (inversión del sujeto pasivo, adquisiciones
    intracomunitarias), que no son ventas;
  - los trimestres son los naturales: en un ejercicio que no empiece el 1 de enero no coincidirían con sus trimestres;
  - una empresa canaria con IVA configurado (rara) solo lo ve en Liquidación.
- **Pruebas:** 76 de 76 en la base de datos y 295 tests de la web. La fase 76 comprueba con el caso completo:
  - que cada trimestre coincide con su liquidación y con la contabilizada; regresión: si contaran los asientos de
    liquidación, el devengado del 1T sería 0;
  - que las retenciones de cada trimestre son las de los modelos;
  - «hasta» a mitad de trimestre, el año anterior, la simulación con una venta en edición, que la liquidación lee
    `erp.tax_accounts`, que otra empresa no ve nada y 95 ms con una empresa grande al lado.

## Cómo explicarlo
- **Devengado frente a deducible:** el IVA / IGIC que se cobra a los clientes no es de la empresa, es de Hacienda; el que
  se paga a los proveedores se recupera. La liquidación es la resta: si se cobró más que se pagó, se ingresa la
  diferencia; si no, se compensa en los trimestres siguientes (o se pide la devolución en el último).
- **Por qué de la contabilidad y no de las facturas:** la liquidación cierra las cuentas 472 / 477 con su saldo; si las
  facturas y la contabilidad no coinciden, la diferencia la enseña la liquidación (cuadre auditor), no la esconde.
- **Por qué sin los asientos de liquidación:** el asiento que salda la 477 contra la 4750 no es IGIC devengado; si
  contara, cada trimestre daría cero.
- **Retenciones:** las practicadas son dinero de terceros que la empresa ingresa por ellos (111, 115, 123); las
  soportadas, un adelanto de su propio Impuesto sobre Sociedades.
- **En BC y SAP:** Business Central tiene el *VAT Statement* y los *VAT Returns*, que leen los *VAT Entries* del
  periodo; SAP S/4HANA, el *Advanced Compliance Reporting* y la *Fiori app* «Tax Reconciliation Account Balance».
  *(Pendiente de validar por Diosvely.)*
