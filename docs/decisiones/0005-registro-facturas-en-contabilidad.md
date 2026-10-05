# ADR 0005 · Registro de facturas desde contabilidad (modelo gestoría)

**Fecha:** 2026-10-02 · **Estado:** aceptada

## Contexto
Para automatizar el IVA/IGIC (con devoluciones, rappels, descuentos por pronto pago y ajustes) hay dos caminos:
un módulo de facturación con artículos (SAP SD/MM, facturas de BC) o registrar las facturas desde la propia
contabilidad (SAP FB60/FB70, registro de facturas de A3ECO / Sage Contabilidad / ContaPlus).

El objetivo del proyecto es **aprender contabilidad española como una gestoría** y analizar empresas como un auditor.

## Decisión
1. Nos quedamos en **contabilidad general** el máximo tiempo posible: no habrá artículos, stock ni pedidos por ahora.
2. Se crea una pantalla **"Registrar factura"** (recibida / emitida, normal / rectificativa):
   cabecera con tercero, nº de factura del proveedor y fecha; líneas con cuenta de base, importe y tipo de IVA/IGIC.
3. Al guardar se genera **el asiento completo** (base + cuota 472/477 + tercero 400/410/430) y el **libro registro**.
4. **Regla del lado:** la cuota va al mismo lado (Debe/Haber) que la línea de base; a la 472 si la base es compra/gasto
   (grupos 2 y 6) y a la 477 si es venta/ingreso (grupo 7). Así devoluciones (608/708), rappels (609/709) y pronto pago
   (606/706) reducen la cuota automáticamente.
5. El cálculo vive en **un único motor de contabilización en la base de datos**, reutilizable por el asiento libre,
   la importación CSV y una futura facturación (como las *posting routines* de BC o la *account determination* de SAP).

## Fases
- **A:** registro de facturas con tipo de impuesto por línea, cuota automática, regla del lado, libro registro completo,
  control de factura duplicada por proveedor (como el *External Document No.* de BC).
- **B:** matriz por territorio (Península / Canarias / UE / extranjero): exportaciones, exentos, inversión del sujeto pasivo.
- **C:** recargo de equivalencia, retenciones IRPF, prorrata y ajustes 634/639.
- **D:** borradores de los modelos 303 (IVA) y 420 (IGIC).

## Consecuencias
- Un futuro módulo de facturación no calculará asientos por su cuenta: llamará al mismo motor.
- Los porcentajes y supuestos fiscales se contrastarán con la normativa vigente al implementarlos (proyecto de estudio,
  no asesoramiento fiscal).
