-- =====================================================================
-- erp.temp_capacity · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0072_temporary_companies   →   la vigente es la de 0072_temporary_companies
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.temp_capacity()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  with s as (select * from erp.temp_settings),
  live as (select id from erp.companies where temporary and not erp.temp_expired(expires_at, last_seen_at)),
  n as (
    select (select count(*) from live)::int as companies,
           ((select count(*) from erp.journal_lines where company_id in (select id from live))
            + (select count(*) from erp.import_lines where company_id in (select id from live)))::int as lines,
           (pg_database_size(current_database()) / 1048576)::int as db_mb
  )
  select jsonb_build_object('companies', n.companies, 'lines', n.lines, 'db_mb', n.db_mb,
    'max_companies', s.max_companies, 'max_total_lines', s.max_total_lines, 'max_db_mb', s.max_db_mb,
    'full', n.companies >= s.max_companies or n.lines >= s.max_total_lines or n.db_mb >= s.max_db_mb)
  from n, s;
$function$
;
