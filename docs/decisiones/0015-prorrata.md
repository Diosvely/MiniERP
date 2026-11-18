# ADR 0015 · Prorrata general aplicada en la factura y regularizada en el 4T

**Fecha:** 2026-10-07 · **Estado:** aceptada

## Contexto
Las empresas que hacen a la vez operaciones con derecho a deducción y operaciones exentas sin ese derecho (una
academia que además vende material, una clínica con servicios estéticos, un arrendador de viviendas y de locales…)
solo deducen una parte del IVA/IGIC soportado: es la prorrata (art. 102 LIVA). Quien solo hace operaciones exentas no
deduce nada.

## Decisión
1. Una fila de `pro_rata` por empresa, impuesto y año con el porcentaje provisional; sin fila, la deducción es total.
2. El motor de facturas reparte cada cuota: 472 por la parte deducible y la cuenta de la compra por el resto,
   como hacen los programas contables habituales, y lo guarda en el libro registro (`deductible_amount`).
3. La definitiva se calcula desde el libro registro de facturas emitidas (bases sin impuesto, unidad superior).
4. La regularización es un asiento a 31/12 (6341 / 6391 contra la 472) que entra en el 303/420 del 4T,
   se puede deshacer hasta liquidar el 4T y fija la provisional del año siguiente.

## Consecuencias
- Simplificaciones del laboratorio: sin prorrata especial, sin sectores diferenciados y sin regularización
  de bienes de inversión de años posteriores.
- El campo `deductible_amount` deja la puerta abierta a esos casos sin cambiar el motor.

*Revisión ética (v0.60.1, 2026-11-08): se quitan los nombres de programas comerciales (ADR 0063). La decisión y sus consecuencias no cambian.*

*Corrección (v0.60.9, 2026-11-18): la prorrata es para quien hace a la vez las dos clases de operaciones (art. 102.Uno
LIVA, «efectúe conjuntamente»; H-46, validado por auditoría fiscal, AF-29).*
