-- =====================================================================
-- erp.can_manage_access · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0085_permissions_ownership   →   la vigente es la de 0085_permissions_ownership
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.can_manage_access(p_company uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  -- sin rol, my_role da NULL y «true and NULL» es NULL: un «if not NULL» no entra y dejaría pasar (lo vio la fase 80)
  select erp.is_owner() and coalesce(erp.my_role(p_company) = 'admin', false);
$function$
;
