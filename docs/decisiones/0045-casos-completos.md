# ADR 0045 · Casos completos y lo que encontraron en el estado de flujos de efectivo

- **Fecha:** 2026-10-25
- **Versión:** v0.45.0
- **Estado:** aceptada

## Contexto

Cada módulo del ERP tiene sus pruebas, con supuestos calculados a mano: facturas, pagos, liquidaciones, inmovilizado,
ajustes de cierre, Impuesto sobre Sociedades, operaciones societarias, financiación y subvenciones. Lo que no se había
probado nunca es **todo junto**: un ejercicio entero, de la constitución a las cuentas anuales, en el que cada módulo
recibe lo que dejó el anterior.

Es lo que pide un examen y lo que hace una gestoría con una empresa nueva. También es la mejor forma de encontrar los
fallos que ningún módulo ve por separado.

## Decisión

1. **Un caso completo, calculado a mano y validado antes de programar** (paso 235): «Taller Atlántico SL», una SL de
   Tenerife (IGIC del 7 %) constituida el 02/01/2026.
   - **Durante el año:** constitución, notaría, asesoría con retención, compras y ventas trimestrales, una máquina con su
     subvención de capital, un préstamo, un seguro y las liquidaciones del IGIC y de las retenciones.
   - **En el cierre:** amortización, imputación de la subvención, intereses devengados, periodificación del seguro,
     deterioro de un cliente dudoso, existencias, Impuesto sobre Sociedades (entidad de nueva creación, al 15 %) y
     cierre.
   - **El motor tiene que dar sus cuentas anuales al céntimo:** cuenta de resultados, balance, ECPN, EFE por los dos
     métodos, impuesto y modelos 420 y 111.
2. **El caso se carga con las funciones de cada módulo** (`erp.load_case`), las mismas que usan las pantallas, con los
   permisos de quien lo carga.
   - Solo en una empresa nueva (sin asientos), canaria y SL, y solo puede cargarlo su administrador.
   - **Catálogo:** `erp.cases`. **Cifras esperadas:** `erp.case_expected` (97 cifras).
   - `erp.case_compare` compara cada cifra con la de la empresa. La prueba fase61 exige que coincidan todas.
3. **Cada diferencia es un fallo que se arregla, con su prueba** (regla A1). La cuenta de resultados, el balance, el
   ECPN, el impuesto y los modelos salieron a la primera. El **EFE** no:
   - **Facturas de inversión o de financiación.** El pago de la máquina al proveedor salía en explotación por el método
     directo, y la notaría de la constitución (113) no restaba de la financiación. Por el indirecto, una máquina sin
     pagar ya salía como inversión. **Ahora el pago o el cobro de una factura se clasifica como lo que compró o
     vendió:**
     - la cuenta del tercero se reparte en la misma proporción que las bases de la factura;
     - se reparte en la factura, en sus pagos o cobros (por lo aplicado) y en sus anulaciones;
     - la base de la 213 va a inversión, la de la 113 a financiación y el IGIC / IVA se queda en explotación.
   - **Intereses devengados y no pagados** (506, 527, 528): iban a financiación. Van con los intereses (A-4 a): mientras
     no se pagan, no hay flujo.
   - **El impuesto que se lleva a reservas** (el ahorro de los gastos de constitución, 6300 / 113): salía como
     financiación sin dinero. Va con el impuesto sobre beneficios (A-4 d).
   - **El deterioro de clientes (490, 493) y de existencias (39):** se veía dentro de la variación del capital
     corriente. Va en los ajustes del resultado (A-2 b), como en el modelo del PGC, y los deudores, por su bruto.
   - **El resultado:** directo = indirecto en cada actividad, y en el caso ya no queda ningún asiento que mezcle
     actividades.
4. **Sin pantalla en esta versión.** La empresa cargada se ve en todas las pantallas que ya existen. La pantalla
   «Casos» (cargar el caso, sus operaciones y la comparación de cifras) llega en la v0.46.0.

## Alternativas descartadas
- **Escribir los asientos del caso a mano** en lugar de llamar a los módulos. Así se prueba el diario, no el ERP. Lo que
  se quería ver es si los módulos encajan.
- **Arreglarlo solo con las cuentas de proveedores de inmovilizado (173 / 523).** El PGC las tiene para eso, pero en la
  práctica la factura de una máquina se registra a menudo contra la 400, y el ERP lo acepta. El EFE tiene que
  clasificar por lo que se compra, no por la cuenta del tercero.
- **Corregir solo el método directo.** El indirecto también se equivocaba con una máquina sin pagar (−40.000 de
  inversión sin haber salido un euro del banco).
- **Dejar el deterioro dentro de los deudores.** El total de explotación es el mismo, pero el modelo del PGC lo pide en
  los ajustes, y así se ve qué parte del resultado no es dinero.

## Consecuencias
- El EFE de cualquier empresa cambia si tiene facturas de inmovilizado o de gastos de constitución, intereses
  devengados, impuesto contra reservas o deterioros. Ahora está mejor clasificado; los totales del año y el efectivo no
  cambian.
- **Limitaciones conocidas:**
  - una anulación de pago se ve en el método directo como un cobro de desinversión, y no como un pago menos (el total
    de la actividad es correcto);
  - los intereses a cobrar devengados (546, 547) siguen en inversión;
  - el auditor avisa de la 113 deudora (−850). Es correcto (NRV 9.ª), pero el paso 11 del asistente queda pendiente
    hasta revisarlo.
- **Pruebas:** 61 de 61 en la base de datos (fase 61) y 227 tests en la web.

## Cómo explicarlo
- **Un módulo bien probado no garantiza un ERP bien probado.** Cada módulo daba sus cifras bien; el fallo estaba en
  cómo se ven juntos en el estado de flujos de efectivo. Por eso los exámenes de contabilidad son casos completos.
- **El EFE pregunta «¿para qué salió el dinero?», no «¿a quién se le pagó?».** Pagar 42.800 al proveedor de la máquina
  no es un pago de explotación: 40.000 son una inversión y 2.800, el IGIC, que se recupera en la liquidación.
- **El devengo no es dinero.** Los intereses devengados y el ahorro de impuesto que va a reservas mueven el resultado o
  el patrimonio, pero no el banco. Si aparecen como flujos, alguien tiene que compensarlos en otra línea, y el EFE deja
  de explicar nada.
- **El deterioro es como la amortización:** es un gasto sin dinero, así que se suma al resultado en los ajustes.
- **En BC y SAP** el EFE suele salir de un informe configurado por cuentas: la 400 de un inmovilizado necesita la 523
  o un ajuste a mano. Aquí sale de las facturas.
