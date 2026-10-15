-- =====================================================================
-- erp.balance_nature · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0013_balance_rules   →   la vigente es la de 0013_balance_rules
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.balance_nature(p_account_no text)
 RETURNS erp.balance_rules
 LANGUAGE sql
 STABLE
AS $function$
  select r.* from erp.balance_rules r
  where p_account_no like r.prefix || '%'
  order by length(r.prefix) desc
  limit 1;
$function$
;
