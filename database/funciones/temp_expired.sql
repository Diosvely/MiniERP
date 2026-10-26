-- =====================================================================
-- erp.temp_expired · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0072_temporary_companies   →   la vigente es la de 0072_temporary_companies
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.temp_expired(p_expires timestamp with time zone, p_last_seen timestamp with time zone)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select now() >= p_expires
      or now() - p_last_seen >= make_interval(mins => (select idle_minutes from erp.temp_settings));
$function$
;
