-- =====================================================================
-- erp.is_admin · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0006_security_rls 0010_tax_setup 0015_guest_access   →   la vigente es la de 0015_guest_access
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.is_admin(p_company uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select not erp.is_anonymous() and coalesce(erp.my_role(p_company) = 'admin', false)
$function$
;
