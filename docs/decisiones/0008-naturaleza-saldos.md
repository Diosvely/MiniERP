# ADR 0008 · Naturaleza de los saldos y saldos anómalos

**Fecha:** 2026-10-05 · **Estado:** aceptada

## Contexto
Un auditor revisa las cuentas con saldo contrario a su naturaleza y propone reclasificaciones al cierre.

## Decisión
1. Catálogo global `balance_rules`: prefijo PGC → naturaleza (deudora / acreedora / mixta), cuenta de
   reclasificación, gravedad y explicación ES/EN. Se aplica el prefijo más largo.
2. Informe de saldos anómalos sobre el balance de sumas y saldos, con el mismo nivel y la misma fecha de corte;
   no se analiza a nivel de grupo o subgrupo porque mezclan naturalezas.
3. Bloqueo opcional por subcuenta (`block_inverse_balance`): impide contabilizar si la cuenta queda al revés.
   Activado por defecto solo en caja (570/571); el resto solo avisa, porque un descubierto bancario es real.

## Consecuencias
- El futuro asistente de cierre podrá proponer los asientos de reclasificación a partir de este informe.
- El balance de situación (siguiente bloque de informes) presentará los saldos inversos en su masa correcta.

## Actualización (v0.60.7, 2026-11-16)

- **Dónde se presentan en el Balance:** el banco en descubierto (572-575 acreedora) va al pasivo corriente, «Deudas con
  entidades de crédito», porque el PGC lo manda (quinta parte, cuentas 572-575: «los descubiertos bancarios […]
  figurarán en todo caso en el pasivo corriente del balance»; AF-18). La caja (570, 571) y la 576 **no** pasan al
  pasivo: una caja acreedora es un error de registro y se presenta restando en la tesorería, con su ⚠ de error (AF-19,
  opción 1; ADR 0064). Al cierre, una caja acreedora sigue siendo un aviso que no impide cerrar (AF-20, pendiente de
  decidir en la v0.60.8).
- Nota de la regla 572: para un descubierto simple, la cuenta del PGC es la 520; la 5201 es para una póliza de crédito.

### Cómo explicarlo
- **El bloqueo y la presentación son dos cosas.** El ERP impide contabilizar una caja en negativo; si llega en un diario
  importado, no la esconde en las deudas: la enseña restando en la tesorería y la marca como error.
