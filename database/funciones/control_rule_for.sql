-- =====================================================================
-- erp.control_rule_for · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0036_controlled_accounts   →   la vigente es la de 0036_controlled_accounts
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.control_rule_for(p_account_no text)
 RETURNS erp.control_rules
 LANGUAGE sql
 STABLE
AS $function$
  select r.* from erp.control_rules r
  where p_account_no like r.account_prefix || '%'
  order by length(r.account_prefix) desc limit 1;
$function$
;
