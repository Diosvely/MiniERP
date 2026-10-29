-- =====================================================================
-- erp.can_report · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0077_large_companies   →   la vigente es la de 0077_large_companies
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.can_report(p_company uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select coalesce(current_setting('role', true), 'none') not in ('authenticated', 'anon') or erp.can_read(p_company);
$function$
;
