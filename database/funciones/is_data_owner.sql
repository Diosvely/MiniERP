-- =====================================================================
-- erp.is_data_owner · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0027_members   →   la vigente es la de 0027_members
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.is_data_owner(p_company uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select exists (select 1 from erp.company_users
                 where company_id = p_company and user_id = auth.uid() and data_owner);
$function$
;
