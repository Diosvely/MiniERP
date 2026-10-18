# ADR 0035 · Ajustes de cierre II: provisiones, deterioro del inmovilizado, existencias y asistente de cierre

- **Fecha:** 2026-10-18
- **Versión:** v0.37.0
- **Estado:** aceptada

## Contexto

La v0.36.0 resolvió las periodificaciones y el deterioro de clientes. Faltaban los otros ajustes del cierre de una pyme
según el PGC 2007:
- las **provisiones** (NRV 15.ª);
- el **deterioro del inmovilizado** (NRV 2.ª 2.2);
- la **regularización de existencias** por inventario (NRV 10.ª);
- un **asistente** que diga qué falta;
- y quedaba pendiente un hallazgo de la v0.35.0: la **rectificativa de una compra de activo** no ajustaba su ficha.

Son cinco piezas. Para cumplir el principio 2 (pasos pequeños, cada uno probado), van en tres migraciones de módulo y
una de integración.

## Decisión

1. **Provisiones** (`erp.provisions` y sus movimientos, migración 0045). Hay tres tipos:

   | Tipo | Largo plazo | Corto plazo | Exceso |
   |---|---|---|---|
   | Impuestos | 141 | 5292 | 7952 |
   | Responsabilidades | 142 | 5293 | 7953 |
   | Operaciones comerciales | — | 4999 | 7954 |

   - **Dotación** con el gasto por naturaleza (633, 678, 62x…); las comerciales, con la 6959.
   - **Revisión** en cada cierre: si sube, más gasto; si baja, exceso a la 795x. En las comerciales se revierte la
     anterior entera y se dota la nueva, como dice el PGC para la 499: no se contabiliza la diferencia neta.
   - **Reclasificación a corto plazo** cuando la obligación vence en menos de un año.
   - **Aplicación al pagar:** si se paga más de lo provisionado, la diferencia va al gasto; si se paga menos, al exceso.
   - **Deshacer** el último movimiento.
   - Se añaden a la plantilla del PGC la **633 y la 638**, que faltaban.
2. **Deterioro del inmovilizado y rectificativas de compra** (`erp.asset_events`, migración 0046).
   - **Deterioro:** si el valor recuperable es menor que el valor neto, la diferencia va a la 69x / 29x.
   - **Reversión:** 29x / 79x, **con el límite** del valor neto que el activo tendría sin el deterioro. El ERP lo
     calcula y lo indica.
   - **Rectificativa de la compra:** su línea a la cuenta del activo **baja el coste de la ficha** (NRV 2.ª 1.1).
   - Cada uno de estos tres hechos es un **suceso** de la ficha. La amortización se calcula **por tramos** entre sucesos:
     lo que queda por amortizar se reparte en los meses de vida que restan. Sin sucesos da lo mismo que antes, al
     céntimo.
   - **Baja:** cancela también el deterioro acumulado (29x D).
3. **Existencias por inventario y asistente de cierre** (`erp.inventory_counts`, migración 0047).
   - Por cada cuenta 30-36, al cierre:
     - baja de la existencia inicial y alta de la final contra la 61x (aprovisionamientos) o la 71x (productos);
     - el deterioro del año anterior se revierte (793x) y se dota el nuevo (693x / 39x).
   - Hay que incluir **todas las cuentas con saldo**, aunque el recuento sea 0. Solo hay un inventario por ejercicio.
   - El **asistente** (`erp.closing_checklist`) devuelve diez pasos en orden. Cada uno está hecho, falta, por revisar
     (lo que el ERP no puede saber, como el valor recuperable o un litigio) o no aplica.
4. **Cuentas controladas:** las provisiones (141, 142, 5292, 5293 y 499), el deterioro del inmovilizado (290, 291 y 292),
   las existencias (30-36) y su deterioro (39).
5. **Integración** (migración 0048):
   - **Comprobaciones nuevas:**
     - las provisiones frente a su módulo;
     - las provisiones sin revisar en el cierre;
     - las existencias frente a sus inventarios.
     La comprobación «inmovilizado frente a sus fichas» ya vigila la 29x.
   - **Avisos del cierre:** inventario sin contabilizar, solo si la empresa tiene cuentas de existencias, y provisiones
     sin revisar.
   - **Glosario:** «Provisión», «Deterioro del inmovilizado» y «Variación de existencias».
6. **Web:**
   - **Ajustes de cierre:** provisiones e inventario, con la vista previa del asiento.
   - **Inmovilizado:** deterioro, reversión y sucesos en la ficha.
   - **Cierre del ejercicio:** el asistente.

## Alternativas descartadas
- **Cuentas 1413, 1415 y 1417** que proponía la revisión externa: no están en el PGC 2007.
- **Revisar las provisiones comerciales por la diferencia neta:** el PGC pide revertir la anterior y dotar la nueva,
  porque así la cuenta de resultados enseña las dos cifras.
- **Recalcular la amortización desde el principio** después de un deterioro: la NRV 2.ª manda repartir el nuevo valor
  en la vida que queda. Por eso se calcula por tramos.
- **Inventario permanente** (fichas de artículos, coste medio y FIFO): queda en «Después» del plan. La pyme española usa
  el recuento del cierre.
- **Precio de última compra:** la NRV 10.ª no lo admite.

## Consecuencias
- El ERP hace los ajustes de cierre habituales de una pyme y guía el orden en que se hacen.
- **Limitación conocida:** la **rectificativa de la venta de un activo** no ajusta el resultado de su baja. La prueba
  al azar la encontró y pasa al backlog.
- **Pruebas:** 43 de 43 en la base de datos y 118 tests en la web.
  - **Fase 40:** provisiones, con su supuesto de referencia calculado a mano.
  - **Fase 41:** deterioro del inmovilizado y rectificativas de compra, con su supuesto.
  - **Fase 42:** existencias y asistente de cierre, con su supuesto.
  - **Fase 43:** la integración.
  - **Fase 34:** todo lo anterior al azar, con cuatro semillas.
