# ADR 0030 · Cobros y pagos contra la factura (Tesorería I)

- **Fecha:** 2026-10-14
- **Versión:** v0.32.0
- **Estado:** aceptada

## Contexto

Hasta ahora un pago era un asiento manual «410 a 572». La factura no sabía si estaba pagada, y la cuenta del tercero
solo daba un saldo, sin detalle. En SAP y en Business Central eso no se puede hacer: la cuenta de proveedores es una
**cuenta controlada** (cuenta asociada en SAP, *Direct Posting* desactivado en BC), y el pago se hace **contra el
tercero y su factura**. Es la «compensación de partidas abiertas» de SAP y la «liquidación» de BC.

El plan de ejecución (`plan-ejecucion.md`) adelanta este módulo al Inmovilizado. Las cuentas controladas
(v0.33.0) necesitan que Pagos exista; si no, el modo estricto bloquearía la 410 sin dar alternativa.

## Decisión

1. **Vencimiento.** Cada tercero tiene sus **días de pago** (`payment_days`), como las condiciones de pago de su ficha
   en BC. La factura vence en su fecha más esos días. Las facturas anteriores vencen en su fecha.
2. **Pagos aplicados a facturas** (`erp.payments`, `erp.payment_applications`; migración 0035):
   - un pago o cobro se aplica a una o varias facturas del mismo tercero, entero o en parte;
   - `erp.post_payment` hace el asiento: pago, acreedor a banco; cobro, banco a cliente;
   - **pendiente = total − retención + rectificativas − pagos**;
   - se rechaza: pagar de más, la factura de otro tercero, una cuenta que no sea 57, aplicar a una rectificativa y
     el tipo de tercero equivocado;
   - **anular** un pago genera un contraasiento y la factura vuelve a quedar pendiente. Su asiento no se anula
     suelto desde el diario, igual que el de una factura.
3. **Vincular pagos hechos a mano** (`erp.link_payment`). Para la contabilidad que ya existía o la importada: un
   asiento manual que mueve la cuenta del tercero se vincula a sus facturas **sin crear otro asiento**. Solo por lo
   que el asiento movió de verdad. Desvincular no toca el asiento.
4. **Partidas abiertas y antigüedad a una fecha** (`erp.open_items`, `erp.aging`):
   - tramos: sin vencer, 1–30, 31–60, 61–90 y más de 90 días;
   - con el **saldo contable** de la subcuenta al lado. Si no coincide con lo pendiente, hay movimientos sin vincular.
     Es el control «después» de los ERP españoles, que convive con el control «antes» de SAP y BC.
5. **Web:**
   - pantalla «Cobros y pagos» con tres pestañas: Pagos, Cobros y Antigüedad de saldos. Antes de registrar se ve el
     asiento que hará el ERP;
   - estado de cada factura (pagada, en parte o pendiente) en el libro registro;
   - nº de asiento enlazado a su ficha;
   - días de pago en la ficha del tercero.

## Alternativas descartadas
- **Cartera de efectos con remesas y vencimientos múltiples por factura:** más propio de la gestión de cobros que de un
  laboratorio contable. Queda para Tesorería II, junto con la conciliación bancaria.
- **Pagos a cuenta y anticipos sin factura:** se siguen haciendo con un asiento manual. Aparecen en la antigüedad como
  diferencia con el saldo contable.
- **Vencimiento editable por factura:** el motor de facturas es inmutable. Los días de pago del tercero cubren el
  caso normal.

## Consecuencias
- La factura sabe si está pagada, y se puede preguntar «¿qué debo y desde cuándo?» a cualquier fecha.
- La base para la v0.33.0 (cuentas controladas) y para las métricas del chat: pendiente de cobro y de pago, días de
  retraso.
- **Pruebas:** 29 de 29 en la base de datos (fase 29 nueva, que falla sin la regla de borrado) y 89 tests de la web.
