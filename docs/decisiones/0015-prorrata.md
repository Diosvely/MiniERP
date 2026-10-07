# ADR 0015 · Prorrata general aplicada en la factura y regularizada en el 4T

**Fecha:** 2026-10-07 · **Estado:** aceptada

## Contexto
Las empresas con actividades exentas sin derecho a deducción (academias, clínicas, aseguradoras, arrendadores
de viviendas) solo deducen una parte del IVA/IGIC soportado.

## Decisión
1. Una fila de `pro_rata` por empresa, impuesto y año con el porcentaje provisional; sin fila, la deducción es total.
2. El motor de facturas reparte cada cuota: 472 por la parte deducible y la cuenta de la compra por el resto,
   como hacen A3 y Sage, y lo guarda en el libro registro (`deductible_amount`).
3. La definitiva se calcula desde el libro registro de facturas emitidas (bases sin impuesto, unidad superior).
4. La regularización es un asiento a 31/12 (6341 / 6391 contra la 472) que entra en el 303/420 del 4T,
   se puede deshacer hasta liquidar el 4T y fija la provisional del año siguiente.

## Consecuencias
- Simplificaciones del laboratorio: sin prorrata especial, sin sectores diferenciados y sin regularización
  de bienes de inversión de años posteriores.
- El campo `deductible_amount` deja la puerta abierta a esos casos sin cambiar el motor.