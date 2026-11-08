-- =====================================================================
-- 0090 · Revisión ética: textos de la base de datos sin nombres de programas comerciales (v0.60.1)
-- ---------------------------------------------------------------------
-- Decisión de Diosvely (07-11-2026 y 08-11-2026, diseno-v0.60.1.md): el contenido es didáctico; no se nombra ni se
-- compara ningún software comercial, y los dos modos de control se explican por lo que hacen, no por quién los usa.
-- Esta migración SOLO cambia textos. No toca ningún cálculo, asiento ni permiso.
--   1. Concepto «Modo estricto o guiado» (erp.concepts, lo usan el Tutor y el chat): control antes (preventivo) o
--      después (posterior). Es la misma fila que src/glossary.js (lo comprueba glossary.test.js).
--   2. Ficha del PGC de la cuenta 112: el ejemplo pasa a ser inventado y redondo (80.000 · 8.000 · 72.000).
--   3. Comentarios de la columna erp.companies.control_mode y de la tabla erp.audit_checks.
-- Prueba: test_fase83_ethics.sql.
-- =====================================================================

-- ---------- 1. Concepto «Modo estricto o guiado» ----------
insert into erp.concepts (key, sort, term, definition, example, term_en, definition_en, example_en, bc, sap, pgc) values
('controlMode', 390, 'Modo estricto o guiado', 'Estricto: solo el módulo mueve la cuenta y un asiento manual sobre ella no se contabiliza (control preventivo, antes de contabilizar). Guiado: el asiento manual se contabiliza con un aviso y queda en Comprobaciones para revisarlo (control posterior).', null, 'Strict or guided mode', 'Strict: only the module posts to the account and a manual entry on it is not posted (preventive control, before posting). Guided: the manual entry is posted with a warning and listed in Checks for review (detective control, afterwards).', null, 'Direct Posting', 'Reconciliation account', '{}')
on conflict (key) do update set
  sort = excluded.sort, term = excluded.term, definition = excluded.definition, example = excluded.example,
  term_en = excluded.term_en, definition_en = excluded.definition_en, example_en = excluded.example_en,
  bc = excluded.bc, sap = excluded.sap, pgc = excluded.pgc;

-- ---------- 2. Ficha de la cuenta 112 (Reserva legal) ----------
update erp.pgc_cards set
  example_text = 'La junta destina el 10 % del beneficio (8.000 €) a reserva legal y el resto a voluntarias.',
  example_lines = '[{"subcuenta": "12900000", "nombre": "Resultado del ejercicio", "debe": 80000, "haber": 0}, {"subcuenta": "11200000", "nombre": "Reserva legal", "debe": 0, "haber": 8000}, {"subcuenta": "11300000", "nombre": "Reservas voluntarias", "debe": 0, "haber": 72000}]'::jsonb,
  warning = 'Mientras no llegue al 20 % del capital, solo puede usarse para compensar pérdidas si no hay otras reservas disponibles.'
where code = '112';

-- ---------- 3. Comentarios del modo de control y de las comprobaciones ----------
comment on column erp.companies.control_mode is
  'strict: manual entries cannot post to controlled accounts (control before) · guided: allowed with warnings, reviewed afterwards (control after).';
comment on table erp.audit_checks is
  'Auditor checks (detective controls, after posting): what is checked, why and where to fix it.';
