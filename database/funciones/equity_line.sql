-- =====================================================================
-- erp.equity_line · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0060_equity_operations   →   la vigente es la de 0060_equity_operations
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.equity_line(p_account uuid, p_debit numeric, p_credit numeric)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select jsonb_build_object('account_id', p_account, 'debit', round(coalesce(p_debit, 0), 2), 'credit', round(coalesce(p_credit, 0), 2));
$function$
;
