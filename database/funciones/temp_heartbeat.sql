-- =====================================================================
-- erp.temp_heartbeat · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0072_temporary_companies   →   la vigente es la de 0072_temporary_companies
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.temp_heartbeat()
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  with u as (
    update erp.companies set last_seen_at = now()
    where created_by = auth.uid() and temporary and not erp.temp_expired(expires_at, last_seen_at)
    returning 1)
  select count(*)::int from u;
$function$
;
