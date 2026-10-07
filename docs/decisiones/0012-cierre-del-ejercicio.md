# ADR 0012 · Cierre del ejercicio con asientos reales y reapertura por contraasientos

**Fecha:** 2026-10-06 · **Estado:** aceptada

## Contexto
Los ERP resuelven el cierre de dos formas: BC y SAP arrastran saldos sin asiento de cierre visible;
A3, Sage y ContaPlus generan los asientos de regularización, cierre y apertura, que es como se enseña en España.

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