-- =====================================================================
-- erp.import_debit · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0021_journal_import   →   la vigente es la de 0021_journal_import
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.import_debit(p_debit numeric, p_credit numeric)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
AS $function$ select greatest(p_debit, 0) + greatest(-p_credit, 0) $function$
;
