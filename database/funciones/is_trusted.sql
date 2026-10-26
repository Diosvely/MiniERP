-- =====================================================================
-- erp.is_trusted · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0072_temporary_companies   →   la vigente es la de 0072_temporary_companies
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.is_trusted()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select not erp.is_anonymous()
     and (erp.is_owner()
          or exists (select 1 from erp.app_profiles where user_id = auth.uid())
          or exists (select 1 from erp.company_users where user_id = auth.uid() and data_owner));
$function$
;
