-- =====================================================================
-- erp.can_use_ai · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0024_ai_context   →   la vigente es la de 0024_ai_context
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.can_use_ai()
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select erp.is_owner();
$function$
;
