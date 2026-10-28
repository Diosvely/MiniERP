-- =====================================================================
-- erp.fs_amounts · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0016_financial_statements 0075_dashboards   →   la vigente es la de 0075_dashboards
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.fs_amounts(p_company uuid, p_year integer, p_statement text, p_to_date date DEFAULT NULL::date)
 RETURNS TABLE(code text, amount numeric)
 LANGUAGE sql
 STABLE
AS $function$
  select a.code, a.amount from erp.fs_amounts_at(p_company, p_year, p_statement, array[p_to_date]) a;
$function$
;
