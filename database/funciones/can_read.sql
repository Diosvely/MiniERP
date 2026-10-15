-- =====================================================================
-- erp.can_read · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0006_security_rls 0007_demo_and_limits   →   la vigente es la de 0007_demo_and_limits
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.can_read(p_company uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select erp.my_role(p_company) is not null
      or exists (select 1 from erp.companies where id = p_company and is_demo);
$function$
;
