-- =====================================================================
-- erp.my_role · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0006_security_rls   →   la vigente es la de 0006_security_rls
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.my_role(p_company uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select role from erp.company_users where company_id = p_company and user_id = auth.uid();
$function$
;
