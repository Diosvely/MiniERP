-- =====================================================================
-- erp.is_owner · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0007_demo_and_limits   →   la vigente es la de 0007_demo_and_limits
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.is_owner()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select exists (select 1 from erp.app_profiles where user_id = auth.uid() and app_role = 'owner');
$function$
;
