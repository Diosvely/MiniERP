# ADR · Estado de flujos de efectivo por los dos métodos

- **Fecha:** 2026-10-08
- **Versión:** v0.20.0
- **Estado:** aceptada

## Contexto

El objetivo del Modo auditor es que el ERP saque por sí mismo lo que los profesionales construyen en Power BI
a partir de un diario importado: balance, PyG, **flujos de efectivo** y ratios. Con las 4 contabilidades reales
importadas en la v0.19.0 (3 de Sage y 1 de Dynamics BC) ya hay datos suficientes para el estado de flujos.

El PGC solo exige el EFE en el modelo normal, y lo presenta por el **método indirecto**. La NIC 7 recomienda el
**método directo**. Para aprender, interesa ver los dos y entender por qué dan el mismo total.

## Decisión

1. **Efectivo = subgrupo 57.** Las pólizas de crédito (520x) son deuda, no efectivo, como en el PGC.
2. **Solo cuentan los asientos normales.** Quedan fuera la apertura, la regularización y el cierre.
3. **Cada subcuenta tiene una única línea de destino** (tabla `cf_mapping`, por el prefijo más largo).
   Su flujo es −(variación de su saldo en el año). Como cada asiento cuadra, la suma de todas las cuentas que no
   son la 57 es exactamente la variación de la 57. Por eso el indirecto **cuadra siempre** por construcción.
4. **Indirecto:**
   - La línea 1 es el resultado antes de impuestos: todas las cuentas de los grupos 6 y 7 salvo la 630, 633 y 638.
   - Lo que no es de explotación (amortización, deterioros, resultados por bajas, intereses, subvenciones)
     se quita en los **ajustes** (línea 2) con signo contrario y se lleva a su línea: intereses en el punto 4,
     y bajas de inmovilizado en inversión.
5. **Directo:** se clasifica la **contrapartida** de cada asiento que mueve la 57.
   - Inversión y deudas se separan en cobros y pagos según el **neto del asiento**. Así la venta de un
     inmovilizado (coste + amortización acumulada + beneficio) es un solo cobro.
6. **Cuadre del auditor** (`cash_flow_check`):
   - Efectivo inicial + flujos = efectivo final.
   - Directo = indirecto = variación de la 57.
   - **Por actividades** los dos métodos pueden diferir. Solo lo explican los **asientos sin dinero que mezclan
     actividades**, y se listan junto con la diferencia que explican.
7. **Rendimiento:** las funciones internas son `SECURITY DEFINER` y no se exponen a la web. Las tres públicas
   (`cash_flow_statement`, `cf_line_accounts` y `cash_flow_check`) comprueban `can_read`. Con la empresa más
   grande (115.000 apuntes), el estado tarda 0,4 s y el cuadre 1,7 s, dentro del límite de 8 s de Supabase.

## Alternativas descartadas

- **Construir el directo a partir del indirecto**, como hacen muchos Excel. Se descarta porque oculta lo
  interesante: qué cobros y pagos reales hubo.
- **Calcular inversión y financiación del indirecto con el directo.** Con eso coincidirían también por
  actividades, pero el indirecto dejaría de cuadrar por construcción y la diferencia se escondería en
  explotación. Es preferible enseñarla.
- **Tratar las pólizas de crédito como efectivo.** La NIC 7 lo admite para descubiertos que forman parte de la
  gestión de tesorería. Se descarta por simplicidad y por coherencia con el PGC.

## Consecuencias

- Con los datos reales salen hallazgos de auditor:
  - **Empresa 3:** inmovilizado comprado a proveedores de explotación en lugar de la 523.
  - **Empresa 2:** pagos a proveedores con cargo a la póliza de crédito.
- **Limitación conocida:** en el indirecto, un dividendo acordado (129 → 526) y pagado en el mismo año aparece
  en patrimonio (IC1) y no en "Pagos por dividendos". El directo sí lo muestra como pago de dividendos.
  El total de financiación es igual por los dos métodos.
- **Base para los ratios del Modo auditor**: la siguiente versión.