# ADR 0011 · Estados financieros que solo leen el diario (preparados para la importación)

**Fecha:** 2026-10-06 · **Estado:** aceptada

## Contexto
Se quiere, más adelante, importar diarios completos de otros ERP (por ejemplo, Business Central) que no pasan
por nuestras facturas ni liquidaciones y cuyas cuentas pueden no seguir el PGC.

## Decisión
1. Balance y PyG (y todos los informes) se calculan SOLO desde los apuntes contabilizados y el plan de cuentas:
   facturas y liquidaciones son submódulos que generan asientos, ningún informe depende de ellos.
2. Estructura (modelo PYMES) y clasificación de cuentas en tablas (`fs_lines`, `fs_mapping`), no en código.
3. Cada subcuenta se clasifica por su propio saldo con doble destino (deudor / acreedor), sin compensar.
4. Importación futura: lote con origen, mapeo "cuenta externa ? subcuenta PGC" con vista previa y todo o nada,
   asientos históricos sin reglas de submódulo (los problemas se señalan, no se bloquean) y empresa propia por importación.

## Consecuencias
- Un diario importado dará los mismos informes que uno registrado a mano.
- Se puede añadir el modelo abreviado o normal ampliando las tablas.