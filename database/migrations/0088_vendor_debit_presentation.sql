-- =====================================================================
-- 0088 · El proveedor con saldo deudor, en Deudores (v0.59.2)
-- ---------------------------------------------------------------------
-- Decisión de Diosvely (05-11-2026, propuesta 3 del parte de estudio): una cuenta con el saldo contrario a su naturaleza
-- se presenta en la partida que le corresponde a ese saldo, sin compensar, y el aviso ⚠ se mantiene.
--
-- Hasta ahora la regla «40» llevaba cualquier 400–409 deudora a EXISTENCIAS (como si fuera un anticipo, la 407), y la
-- 410 deudora a OTROS DEUDORES: dos criterios distintos para el mismo caso. Si la empresa sigue el PGC, un anticipo de
-- verdad se registra en la 407; un proveedor deudor es casi siempre un pago duplicado, un abono pendiente o una factura
-- sin registrar: un derecho de cobro. Llevarlo a Existencias además infla las existencias y cambia los ratios.
--
--   · 400–405 y 408–409 deudoras → AC.II.3 «Otros deudores» (como la 410 deudora).
--   · 407 (anticipos a proveedores) → Existencias, su sitio en el modelo de balance del PGC.
--   · 406 (envases a devolver a proveedores) → Proveedores, restando, su sitio en el modelo de balance del PGC.
--   · Las notas del aviso dicen qué revisar: la 400 deudora (anticipo → 407; pago duplicado o abono → derecho de cobro) y
--     el banco acreedor (el balance ya lo presenta en el pasivo; el asiento a la 5201, si se hace, se revierte al abrir).
-- =====================================================================

-- ---------- La partida de cada saldo ----------
update erp.fs_mapping set debit_line = 'AC.II.3' where statement = 'balance' and prefix = '40';
insert into erp.fs_mapping (statement, prefix, debit_line, credit_line) values
  ('balance', '407', 'AC.I', 'PC.IV.1'),       -- anticipos a proveedores: en Existencias (si fuera acreedora, con Proveedores)
  ('balance', '406', 'PC.IV.1', 'PC.IV.1')     -- envases a devolver a proveedores: en Proveedores, restando
on conflict (statement, prefix) do update set debit_line = excluded.debit_line, credit_line = excluded.credit_line;

-- ---------- Las notas del aviso ⚠ ----------
update erp.balance_rules set reclass_to = null,
  note = 'Proveedor con saldo deudor: se presenta en Otros deudores, sin compensar con los demás proveedores. Revisa su mayor: si es un anticipo, llévalo a la 407; si es un pago duplicado o un abono pendiente, es un derecho de cobro.',
  note_en = 'Vendor with a debit balance: presented in Other receivables, not offset against the other vendors. Check its ledger: if it is an advance, move it to 407; if it is a duplicate payment or a pending credit, it is a receivable.'
where prefix = '400';
update erp.balance_rules set
  note = 'Banco con saldo acreedor: descubierto o póliza de crédito. El balance ya lo presenta en Deudas con entidades de crédito. Si haces el asiento de reclasificación a la 5201 al cierre, reviértelo al abrir el ejercicio siguiente para que el mayor del banco siga cuadrando con el extracto.',
  note_en = 'Bank with a credit balance: overdraft or credit line. The balance sheet already presents it in Bank borrowings. If you post the reclassification to 5201 at year end, reverse it when the next year opens so that the bank ledger still matches the statement.'
where prefix = '572';
