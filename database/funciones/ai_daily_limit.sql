-- =====================================================================
-- erp.ai_daily_limit · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0072_temporary_companies   →   la vigente es la de 0072_temporary_companies
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.ai_daily_limit()
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select case when erp.is_owner() then null
              else coalesce((select ai_daily_limit from erp.app_profiles where user_id = auth.uid()),
                            case when erp.is_trusted() then 10 else (select ai_daily_limit from erp.temp_settings) end) end;
$function$
;
