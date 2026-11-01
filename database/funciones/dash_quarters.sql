-- =====================================================================
-- erp.dash_quarters · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0082_tax_dashboard   →   la vigente es la de 0082_tax_dashboard
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.dash_quarters(p_months date[], p_series jsonb, p_cur jsonb, p_to date, p_code text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
  with q as (
    select extract(quarter from e)::int as qn, e, (p_series -> (n::int - 1)) as v
    from unnest(p_months) with ordinality m(e, n)
  ), acum as (
    select qn,
           -- el acumulado a fin de trimestre: el de su último mes si tiene dato o, si «hasta» cae dentro, el de «hasta»
           case when (array_agg(v order by e desc))[1] is not null and (array_agg(v order by e desc))[1] <> 'null'::jsonb then
                  ((array_agg(v order by e desc))[1] ->> p_code)::numeric
                when p_to is not null and p_cur is not null and p_to between date_trunc('quarter', max(e))::date and max(e) then
                  (p_cur ->> p_code)::numeric
           end as a
    from q group by qn
  ), d as (
    select qn, a, a - coalesce(lag(a) over (order by qn), 0) as v from acum
  )
  select coalesce(jsonb_agg(case when a is null then null else to_jsonb(v) end order by qn), '[]') from d;
$function$
;
