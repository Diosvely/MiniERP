# ADR 0064 · El Balance compensado, el menú «Auditorías» y la caja en su sitio

- **Fecha:** 2026-11-16
- **Versión:** v0.60.7
- **Estado:** aceptada (Diosvely, 15 y 16-11-2026; AF-18 y AF-19 de auditoría fiscal, opción 1 de AF-19).

## Contexto

El Mini ERP no compensa: cada subcuenta va a su lado del Balance según su propio saldo (ADR 0057 y 0061). Pero no
enseñaba **cuánto engañaría** un Balance compensado, que es lo que sale cuando se suman todas las subcuentas de un
subgrupo y el neto se pone en un solo lado: cuadra igual, pero esconde deudas y los ratios de liquidez salen mucho
mejores de lo que son.

Al preparar la empresa de práctica del vídeo 03 (un banco con dinero, otro en descubierto y la caja en negativo),
auditoría fiscal revisó dónde presenta el ERP un saldo acreedor en el subgrupo 57:

- **AF-18 (validado):** el banco en descubierto (572-575 acreedora) va a «Deudas con entidades de crédito» del pasivo
  corriente, como dice el PGC: «los descubiertos bancarios […] figurarán en todo caso en el pasivo corriente del
  balance» (RD 1514/2007 y RD 1515/2007, quinta parte, cuentas 572-575).
- **AF-19 (error):** la caja acreedora (570, 571) y la 576 acreedora iban también a «Deudas con entidades de
  crédito». Una caja no puede deber dinero a un banco: el saldo acreedor es un error de registro (falta un cobro o
  sobra un pago). La regla del descubierto está escrita solo para las cuentas 572-575.

## Decisión

1. **La caja (570, 571) y la 576 no pasan nunca al pasivo** (AF-19, opción 1). Se presentan en Tesorería / Efectivo
   del activo, restando si su saldo es acreedor, con su ⚠ (la regla de saldos ya la marca como error). Los tres
   modelos (PYMES, abreviado y normal). El descubierto bancario sigue en el pasivo (AF-18). Es **criterio** del ERP:
   el PGC no dice dónde presentar un error de registro, porque las cuentas anuales se formulan después de corregirlo.
2. **El Balance compensado, solo para enseñar** (`erp.fs_compensated` y `erp.fs_compensated_ratios`). Cada partida
   con dos importes: el del ERP (sin compensar) y el que saldría compensando. Compensar es sumar las subcuentas de un
   mismo subgrupo (dos dígitos) que van a la misma pareja de partidas (deudora / acreedora) y poner el neto en un solo
   lado. Los ratios de los dos: liquidez general, prueba ácida, tesorería inmediata y endeudamiento, el fondo de
   maniobra (no cambia) y lo escondido (total del activo sin compensar menos compensado). Las fórmulas son las de
   `erp.financial_ratios`, así que los ratios «sin compensar» son los de la pantalla Ratios.
3. **En la pantalla del Balance, «Comparar con»:** «Ejercicio anterior» (por defecto, lo de siempre) o «Compensado»
   (sin compensar · compensado · diferencia · %, un aviso con lo escondido y cuatro tarjetas de ratios).
4. **Menú «Auditorías» en la barra superior,** al lado de «Tableros». Cada tablero del catálogo lleva su grupo
   (`erp.dashboards.area`: `tablero` o `auditoria`). En auditorías: «Calidad de la contabilidad» (el de siempre) y
   «Saldos al revés» (nuevo). Las direcciones de los tableros no cambian.
5. **Tablero «Saldos al revés»:** un tipo de tarjeta nuevo (`reverse_cards`, con `erp.reverse_cards`). Una tarjeta por
   cada subcuenta con saldo contrario a su naturaleza: lo que debería ser, el importe, «imposible» (error) o
   «revisar» (aviso), la partida en la que la presenta el Balance en el modelo elegido, la nota de la regla, la
   pregunta de un auditor y el enlace a su libro mayor. Un resumen arriba que también filtra.

## Consecuencias

- Ningún asiento ni ningún saldo cambia. Con la caja en negativo cambian el efectivo, el pasivo corriente y los ratios
  de liquidez: en la empresa de práctica del vídeo 03, la prueba ácida pasa de 3,32 a 3,87 (compensado: 19,46).
- Las comprobaciones que ya había siguen igual: la caja acreedora es error en las comprobaciones del auditor, en el
  tablero de calidad y en el Balance; la vista previa del cierre sigue avisando sin impedir cerrar (AF-20 queda para
  la v0.60.8).
- Un tablero nuevo de auditor solo necesita `area = 'auditoria'` en el catálogo para salir en su menú.
- Pruebas: fase 82 (AF-19 en los tres modelos), fase 78 (el ⚠ de la caja, ahora en el efectivo) y fase 84 (un diario
  importado con cifras que se rehacen a mano: Balance compensado, ratios, simulación, tarjetas y permisos). Web: el
  reparto de los tableros, el resumen y el filtro de las tarjetas y las veces que exagera el compensado.

## Alternativas descartadas

- **AF-19, opción 2:** la caja acreedora en «Otras deudas a corto plazo». No dice «banco», pero sigue inventando un
  pasivo.
- **AF-19, opción 3:** dejarla como estaba y solo documentarlo.
- **Compensar por partida en vez de por subgrupo:** escondería todavía más (por ejemplo, todos los créditos con
  Hacienda en una sola cifra) y no es lo que hace quien compensa a mano en una hoja de cálculo.
- **Guardar el Balance compensado:** es una vista de estudio; se calcula al pedirla y no se guarda nada.

## Cómo explicarlo

- **Cuadrar no es estar bien.** Un Balance compensado cuadra igual: si se resta el descubierto del Banco Norte del
  dinero del Banco Sur, el activo y el pasivo bajan lo mismo. Por eso el fondo de maniobra no cambia y el fallo no se
  ve con él; se ve en los ratios. Con menos pasivo corriente, la prueba ácida se dispara.
- **Un descubierto es una deuda; una caja en negativo es un error.** El banco te ha prestado ese dinero: va al
  pasivo. De una caja no se puede sacar más dinero del que hay: si queda en negativo, falta un cobro o sobra un pago.
  No se reclasifica: se corrige. Mientras tanto, resta en la tesorería y avisa.
- **Las cuentas anuales nunca compensan** (PGC, Marco Conceptual, apartado 3.º, principio de no compensación), salvo
  que una norma lo permita expresamente. El Mini ERP enseña el Balance compensado solo para ver lo que esconde.
