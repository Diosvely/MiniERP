-- =====================================================================
-- erp.temp_leave · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0072_temporary_companies   →   la vigente es la de 0072_temporary_companies
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.temp_leave()
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  with u as (
    update erp.companies
       set last_seen_at = least(last_seen_at, now() - make_interval(mins => (select idle_minutes - 10 from erp.temp_settings)))
     where created_by = auth.uid() and temporary
    returning 1)
  select count(*)::int from u;
$function$
;
