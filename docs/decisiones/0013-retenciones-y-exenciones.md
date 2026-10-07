# ADR 0013 · Retención IRPF en la factura y causas de las operaciones sin cuota

**Fecha:** 2026-10-07 · **Estado:** aceptada

## Contexto
Un tipo "0 %" genérico no dice por qué no hay impuesto, y el libro registro, el SII y las casillas del 303/420
sí lo necesitan. Las retenciones de profesionales y alquileres son diarias en una gestoría.

## Decisión
1. Un código de impuesto por causa (E1, E2, E5, N2) en `tax_codes`, con `exemption_key`, igual que en
   los grupos de IVA de BC o los indicadores de impuesto de SAP.
2. El motor de facturas comprueba las condiciones de cada causa: tipo de factura y territorio del tercero.
3. La retención va en la cabecera de la factura, sobre la base neta. Tablas `withholding_codes` y `withholding_setup`
   con cuentas 4751 por modelo (111 / 115) y 473 para las soportadas.
4. Las retenciones se configuran solas al configurar el IVA / IGIC, sin pasos extra para el usuario.
5. El pago del 111 / 115 y las retenciones de nóminas son asientos manuales: es lo que se enseña y practica.

## Consecuencias
- El libro registro y el borrador del 303/420 muestran cada base sin cuota con su causa.
- Una factura mal planteada (exportar a un cliente de tu territorio) da error en vez de quedar mal declarada.