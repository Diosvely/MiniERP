-- =====================================================================
-- erp.ai_allowed · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0027_members   →   la vigente es la de 0027_members
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.ai_allowed(p_company uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select (erp.is_owner() and erp.can_read(p_company)) or erp.is_data_owner(p_company);
$function$
;
