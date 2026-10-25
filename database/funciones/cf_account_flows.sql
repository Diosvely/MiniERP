-- =====================================================================
-- erp.cf_account_flows · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0022_cash_flow 0066_complete_case   →   la vigente es la de 0066_complete_case
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.cf_account_flows(p_company uuid, p_year integer)
 RETURNS TABLE(account_no text, account_name text, account_name_en text, flow numeric, home_line text, adjust_line text, direct_line text, in_result boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select f.account_no, f.account_name, f.account_name_en, sum(f.flow), f.home_line, f.adjust_line, f.direct_line, f.in_result
  from erp.cf_line_flows(p_company, p_year) f
  group by f.account_no, f.account_name, f.account_name_en, f.home_line, f.adjust_line, f.direct_line, f.in_result
  having sum(f.flow) <> 0;
$function$
;
