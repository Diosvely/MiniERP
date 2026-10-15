-- =====================================================================
-- erp.cf_account_map · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0022_cash_flow   →   la vigente es la de 0022_cash_flow
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.cf_account_map(p_account_no text)
 RETURNS erp.cf_mapping
 LANGUAGE sql
 STABLE
AS $function$
  select m.* from erp.cf_mapping m where p_account_no like m.prefix || '%' order by length(m.prefix) desc limit 1;
$function$
;
