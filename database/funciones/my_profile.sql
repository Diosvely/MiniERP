-- =====================================================================
-- erp.my_profile · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0007_demo_and_limits 0015_guest_access 0072_temporary_companies   →   la vigente es la de 0072_temporary_companies
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.my_profile()
 RETURNS TABLE(app_role text, max_companies integer, companies_created integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select case when erp.is_anonymous() then 'guest' else coalesce(p.app_role, 'member') end,
         case when erp.is_anonymous() then 0 when p.user_id is null then 1 else p.max_companies end,
         (select count(*)::int from erp.companies c where c.created_by = auth.uid() and not c.temporary)
  from (select auth.uid() as uid) me
  left join erp.app_profiles p on p.user_id = me.uid;
$function$
;
