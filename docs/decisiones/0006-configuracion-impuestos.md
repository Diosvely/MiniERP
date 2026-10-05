# ADR 0006 · Configuración de impuestos por empresa

**Fecha:** 2026-10-04 · **Estado:** aceptada

## Contexto
Para registrar facturas (J3) el sistema debe saber a qué subcuenta va la cuota de cada tipo de IVA/IGIC.

## Decisión
1. Tabla `tax_setup`: por empresa y tipo, subcuenta de soportado (472) y de repercutido (477),
   como el *VAT Posting Setup* de BC y la OB40 de SAP.
2. Tabla `tax_settlement_setup`: por impuesto, subcuentas de la liquidación 4750 (a ingresar) y 4700 (a devolver).
3. Asistente que crea las subcuentas según el territorio: Canarias ? IGIC, resto ? IVA (se puede añadir el otro).
   Convención: 472**0**xxxx IVA / 472**1**xxxx IGIC; xxxx = tipo (0021 = 21 %, 0095 = 9,5 %).
4. Los tipos 0 % no llevan cuenta: no generan cuota, solo base para el libro registro.
5. La base de datos valida las reglas contables; solo el administrador de la empresa configura.
6. Un apunte en una cuenta de impuesto configurada toma su tipo automáticamente.

## Consecuencias
- J3 (facturas) y J4 (liquidación) leerán estas tablas: ninguna pantalla decide cuentas por su cuenta.
- Recargo de equivalencia, prorrata e inversión del sujeto pasivo se añadirán en J5.