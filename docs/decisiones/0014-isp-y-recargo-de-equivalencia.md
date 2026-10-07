# ADR 0014 · Inversión del sujeto pasivo y recargo de equivalencia como códigos de impuesto

**Fecha:** 2026-10-07 · **Estado:** aceptada

## Contexto
ISP, adquisiciones intracomunitarias y recargo de equivalencia cambian quién declara el impuesto y si se deduce,
pero el usuario debe registrarlos con el mismo formulario de factura.

## Decisión
1. ISP y AIB son códigos de impuesto propios (categoría `reverse_charge` / `intra_eu_acquisition`), como los
   "Reverse Charge VAT" de BC o los códigos de autorrepercusión de SAP, con subcuentas 472/477 separadas.
2. El recargo de equivalencia no es un código: depende del CLIENTE (marca en el tercero) o de la EMPRESA
   (régimen de IVA). Su cuenta (4770 7…) cuelga de cada tipo de IVA en la configuración.
3. El libro registro guarda por tipo: base, cuota, recargo y si es deducible (`deductible`), para que la liquidación
   no dependa de reglas escondidas. La prorrata usará el mismo campo.
4. Las cuentas especiales se crean solas con un trigger al configurar el tipo: el usuario no configura nada nuevo.

## Consecuencias
- Simplificaciones del laboratorio: el minorista en recargo vende con VAT_RE_INC y no puede usar ISP.
- Las importaciones con DUA (IVA o IGIC de importación) quedan fuera por ahora.