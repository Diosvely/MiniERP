# ADR 0008 · Naturaleza de los saldos y saldos anómalos

**Fecha:** 2026-10-05 · **Estado:** aceptada

## Contexto
Un auditor revisa las cuentas con saldo contrario a su naturaleza y propone reclasificaciones al cierre.

## Decisión
1. Catálogo global `balance_rules`: prefijo PGC ? naturaleza (deudora / acreedora / mixta), cuenta de
   reclasificación, gravedad y explicación ES/EN. Se aplica el prefijo más largo.
2. Informe de saldos anómalos sobre el balance de sumas y saldos, con el mismo nivel y la misma fecha de corte;
   no se analiza a nivel de grupo o subgrupo porque mezclan naturalezas.
3. Bloqueo opcional por subcuenta (`block_inverse_balance`): impide contabilizar si la cuenta queda al revés.
   Activado por defecto solo en caja (570/571); el resto solo avisa, porque un descubierto bancario es real.

## Consecuencias
- El futuro asistente de cierre podrá proponer los asientos de reclasificación a partir de este informe.
- El balance de situación (siguiente bloque de informes) presentará los saldos inversos en su masa correcta.