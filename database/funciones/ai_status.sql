-- =====================================================================
-- erp.ai_status · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0027_members   →   la vigente es la de 0027_members
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
    'limit', case when erp.is_owner() then null
                  else coalesce((select ai_daily_limit from erp.app_profiles where user_id = auth.uid()), 10) end);
$function$
;
