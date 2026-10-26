-- =====================================================================
-- erp.ai_status · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0027_members 0072_temporary_companies   →   la vigente es la de 0072_temporary_companies
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.ai_status(p_company uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select jsonb_build_object(
    'allowed', erp.ai_allowed(p_company),
    'used', coalesce((select calls from erp.ai_usage where user_id = auth.uid() and used_on = current_date), 0),
    'limit', erp.ai_daily_limit());
$function$
;
