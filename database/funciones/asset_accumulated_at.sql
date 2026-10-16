-- =====================================================================
-- erp.asset_accumulated_at · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0041_fixed_assets   →   la vigente es la de 0041_fixed_assets
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.asset_accumulated_at(p_cost numeric, p_residual numeric, p_life integer, p_start date, p_date date)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
AS $function$
  with a as (select p_cost - p_residual as base, (p_date + 1) as d1),
  m as (select a.*, (extract(year from age(a.d1, p_start)) * 12 + extract(month from age(a.d1, p_start)))::int as months from a),
  f as (select m.*, (p_start + make_interval(months => m.months))::date as from_d,
               (p_start + make_interval(months => m.months + 1))::date as to_d from m)
  select case when p_date < p_start then 0
              else least(f.base, round(f.base * (f.months + (f.d1 - f.from_d)::numeric / (f.to_d - f.from_d)) / p_life, 2)) end
  from f;
$function$
;
