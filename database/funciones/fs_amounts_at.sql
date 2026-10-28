-- =====================================================================
-- erp.fs_amounts_at · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0075_dashboards   →   la vigente es la de 0075_dashboards
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.fs_amounts_at(p_company uuid, p_year integer, p_statement text, p_dates date[])
 RETURNS TABLE(at date, code text, amount numeric)
 LANGUAGE sql
 STABLE
AS $function$
  with recursive up(code, ancestor) as (
    select l.code, l.code from erp.fs_lines l where l.statement = p_statement
    union all
    select up.code, p.parent
    from up join erp.fs_lines p on p.statement = p_statement and p.code = up.ancestor
    where p.parent is not null
  ), detail as (
    select c.at, c.line_code, sum(c.amount) as amount
    from erp.fs_classified_at(p_company, p_year, p_statement, p_dates) c
    group by c.at, c.line_code
  ), dates as (select distinct x as at from unnest(p_dates) x)
  select dt.at, up.ancestor, coalesce(sum(d.amount), 0)
  from dates dt cross join up
  left join detail d on d.line_code = up.code and d.at is not distinct from dt.at
  group by dt.at, up.ancestor;
$function$
;
