# ADR 0034 · Ajustes de cierre I: periodificaciones y deterioro de clientes

- **Fecha:** 2026-10-18
- **Versión:** v0.36.0
- **Estado:** aceptada

## Contexto

Antes de cerrar un ejercicio, el PGC exige dos ajustes que el ERP no sabía hacer:

- **Periodificar** según el principio de devengo (marco conceptual): llevar cada gasto e ingreso al año al que
  corresponde, se pague o se cobre cuando sea.
- **Deteriorar** los clientes de dudoso cobro (NRV 9.ª).

Se hacían con asientos manuales, que nadie revertía al año siguiente y que ninguna comprobación vigilaba. Es la primera
parte del bloque «Fin de ejercicio» del plan revisado el 18-10-2026, que ahora va en dos versiones para cumplir el
principio 2 del plan.

## Decisión

1. **Periodificaciones** (`erp.accruals`, migración 0043). Son cuatro tipos y todos van contra la **propia cuenta de
   gasto o ingreso**, sin cuentas puente:

   | Tipo | Asiento al cierre |
   |---|---|
   | Gasto anticipado | 480 D / 6xx H |
   | Ingreso anticipado | 7xx D / 485 H |
   | Gasto sin factura | 6xx D / 4009 H |
   | Ingreso sin facturar | 4309 D / 7xx H |

   - El importe se puede escribir directamente o calcular **por meses** a partir del total y del periodo que cubre. El
     primer mes se cuenta por días, con la misma regla que la amortización.
   - La **reversión** del año siguiente es un **asiento nuevo**, no un contraasiento. Si fuera una anulación, los
     informes del año del cierre perderían la 480.
2. **Deterioro de clientes** (`erp.receivable_impairments` y `erp.receivable_writeoffs`). La deuda **sigue en la 430**
   con su partida abierta, y la 490 la corrige. No se reclasifica a la 436, para no romper el cuadre entre el tercero y
   sus facturas.
   - **Deterioro individual** sobre lo pendiente de una factura: 694 D / 490 H.
   - **Deterioro global** por cinco tramos de antigüedad. Excluye las facturas con deterioro individual. Solo puede haber
     uno vivo, porque se vuelve a estimar en cada cierre.
   - **Reversión** cuando el cliente paga o cambia la estimación: 490 D / 794 H.
   - **Insolvencia firme:** 650 D / 430 H por lo pendiente, y se aplica el deterioro que tenía (490 D / 794 H). La partida
     abierta se cierra **como un cobro sin banco**: es la compensación de partidas de SAP o la liquidación de BC.
3. **Avisos fiscales** (Ley 27/2014 del IS). Avisan, pero no bloquean:
   - el deterioro individual es deducible desde los 6 meses del vencimiento (art. 13.1.a);
   - el global no es deducible (art. 13.1), salvo para las empresas de reducida dimensión, que pueden deducir hasta el 1 %
     de los deudores (art. 104). El ERP calcula ese tope.
4. **Controles:**
   - la 480, la 485, la 4009 y la 4309 pasan a ser **cuentas controladas** por Periodificaciones, y la 490 por Deterioro;
   - todo se deshace desde el módulo, con «deshacer el último paso». Nunca desde el diario ni desde Cobros y pagos.
5. **Integración** (migración 0044):
   - tres comprobaciones del auditor: las cuentas frente a sus fichas, las periodificaciones del año anterior sin revertir
     y los deterioros de facturas ya cobradas;
   - el cierre avisa de las periodificaciones sin revertir;
   - el glosario recoge «Periodificación» y «Deterioro de clientes»;
   - la prueba de operaciones al azar hace los ajustes de cierre, los revierte, cobra e incluye una insolvencia firme.
6. **Web:** pantalla **Ajustes de cierre**, con:
   - la lista de periodificaciones, su alta con vista previa del asiento y la reversión de todas las pendientes;
   - los clientes pendientes a la fecha, con «Deteriorar» e «Insolvencia», y el global por tramos con vista previa;
   - el historial;
   - un enlace desde Cierre del ejercicio.

## Alternativas descartadas
- **Cuentas 680/685 y 780/785 para periodificar**, como proponía la revisión externa: la 680 es la amortización del
  intangible, y la 685 y la 780 no existen en el PGC 2007.
- **Revertir con un contraasiento:** el año del cierre perdería el ajuste en los informes.
- **Reclasificar a la 436 (clientes de dudoso cobro):** el PGC lo admite, pero rompería la partida abierta y el cuadre
  tercero-facturas. La 490 basta.
- **Bloquear los deterioros no deducibles:** la contabilidad sigue la NRV 9.ª. Lo fiscal es un ajuste en el Impuesto
  sobre Sociedades.

## Consecuencias
- El ERP hace dos de los ajustes de cierre típicos de una pyme, con su asiento, su reversión y su vigilancia.
- **Fuera de esta versión:** la modificación de la base imponible del IVA por impago (art. 80.Cuatro LIVA). Se hace con
  la factura rectificativa, que ya existe; después, la insolvencia sobre lo que quede.
- **Pruebas:** 39 de 39 en la base de datos y 112 tests en la web.
  - **Fase 38:** el supuesto de referencia, calculado a mano.
  - **Fase 39:** la integración.
  - **Fase 34:** los ajustes en la prueba al azar, con cuatro semillas.
