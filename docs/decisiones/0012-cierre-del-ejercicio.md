# ADR 0012 · Cierre del ejercicio con asientos reales y reapertura por contraasientos

**Fecha:** 2026-10-06 · **Estado:** aceptada

## Contexto
El cierre se puede resolver de dos formas: arrastrar los saldos sin un asiento de cierre visible, o generar los
asientos de regularización, cierre y apertura, que es como se enseña en España.

*Revisión ética (v0.60.5, 2026-11-14): la comparación ya no enfrenta a dos grupos de programas. La decisión no cambia.*

## Decisión
1. Se generan los tres asientos clásicos (regularización, cierre y apertura) de tipos `closing_pl`, `closing` y `opening`,
   porque el objetivo del laboratorio es aprender a leerlos.
2. Un asistente comprueba antes de cerrar. Los errores bloquean (borradores, ejercicio anterior abierto);
   los avisos hay que aceptarlos (trimestres de IVA/IGIC sin liquidar, saldos anómalos graves).
3. Reabrir anula los tres asientos con contraasientos, sin borrar nada, como SAP: queda la traza para el auditor.
4. Los ejercicios se cierran en orden y se reabren en orden inverso.
5. Balance y PyG excluyen regularización y cierre; la apertura sí cuenta como saldo inicial.
6. La aplicación del resultado (129 → reservas / 121 / dividendos) es un asiento manual del año siguiente.

## Consecuencias
- Si en el año nuevo ya había asientos, la apertura no es el nº 1: no se renumera lo contabilizado.
- Los asientos del cierre no cuentan como movimiento de IVA/IGIC ni entran en el libro registro.

*Revisión ética (v0.60.1, 2026-11-08): se quitan los nombres de programas comerciales (ADR 0063). La decisión y sus consecuencias no cambian.*
