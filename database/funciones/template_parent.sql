-- =====================================================================
-- erp.template_parent · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0008_import_accounts   →   la vigente es la de 0008_import_accounts
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.template_parent(p_account_no text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  select account_no from erp.coa_template
  where p_account_no like account_no || '%' and level >= 3
  order by level desc
  limit 1;
$function$
;
