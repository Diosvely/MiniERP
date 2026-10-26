-- =====================================================================
-- erp.temp_status · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0072_temporary_companies   →   la vigente es la de 0072_temporary_companies
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.temp_status()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select jsonb_build_object(
    'mode', case when erp.is_anonymous() then 'none' when erp.is_trusted() then 'permanent' else 'temporary' end,
    'idle_minutes', s.idle_minutes, 'max_hours', s.max_hours, 'max_lines_per_import', s.max_lines_per_import,
    'ai_daily_limit', s.ai_daily_limit,
    'company', (select jsonb_build_object('id', c.id, 'name', c.name, 'expires_at', c.expires_at, 'last_seen_at', c.last_seen_at,
                                          'delete_at', least(c.expires_at, c.last_seen_at + make_interval(mins => s.idle_minutes)))
                from erp.companies c where c.created_by = auth.uid() and c.temporary
                  and not erp.temp_expired(c.expires_at, c.last_seen_at)
                order by c.created_at desc limit 1),
    'full', (erp.temp_capacity()->>'full')::boolean)
  from erp.temp_settings s;
$function$
;
