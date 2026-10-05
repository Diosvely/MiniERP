# ADR 0007 · Liquidación trimestral de IVA / IGIC

**Fecha:** 2026-10-05 · **Estado:** aceptada

## Contexto
Las cuotas de 472/477 se saldan cada trimestre contra Hacienda (modelos 303 IVA / 420 IGIC).

## Decisión
1. Borrador calculado en la base de datos: casillas por tipo desde el libro registro y asiento desde los saldos
   de las cuentas de impuesto del trimestre (como *Calc. and Post VAT Settlement* de BC).
2. Resultado positivo ? 4750 · negativo ? 4700 (a compensar; en el 4T se puede pedir devolución).
   La compensación de periodos anteriores se aplica automáticamente.
3. Cuadre obligatorio libro registro ? contabilidad; la diferencia solo se admite aceptándola y queda guardada.
4. El trimestre liquidado se bloquea para nuevos apuntes en cuentas de impuesto; la factura tardía usa una
   fecha de registro posterior.
5. Solo se puede deshacer la última liquidación y siempre con contraasiento.

## Fuera de alcance (por ahora)
Declaración mensual (grandes empresas / REDEME), límite temporal de compensación, prorrata, regularización de
bienes de inversión y presentación telemática. Contrastar plazos y reglas con la AEAT y la ATC.