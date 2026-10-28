-- =====================================================================
-- erp.dash_month_ends · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0075_dashboards   →   la vigente es la de 0075_dashboards
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.dash_month_ends(p_start date, p_end date)
 RETURNS date[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select coalesce(array_agg(d order by d), '{}')
  from (select (date_trunc('month', g) + interval '1 month - 1 day')::date as d
        from generate_series(date_trunc('month', p_start), date_trunc('month', p_end), interval '1 month') g) x;
$function$
;
