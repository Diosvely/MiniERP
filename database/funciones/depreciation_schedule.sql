-- =====================================================================
-- erp.depreciation_schedule · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0041_fixed_assets 0046_asset_impairment   →   la vigente es la de 0046_asset_impairment
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.depreciation_schedule(p_asset uuid)
 RETURNS TABLE(year integer, amount numeric, accumulated numeric, net_book_value numeric)
 LANGUAGE sql
 STABLE
AS $function$
  with a as (select * from erp.fixed_assets where id = p_asset),
  y as (select generate_series(extract(year from a.start_date)::int,
                               extract(year from (a.start_date + make_interval(months => a.useful_life_months)))::int) as yr from a),
  c as (select y.yr, erp.asset_depr_at(a.id, make_date(y.yr, 12, 31)) as acc
        from y cross join a)
  select c.yr, c.acc - coalesce(lag(c.acc) over (order by c.yr), 0), c.acc, erp.asset_cost_at(p_asset, make_date(c.yr, 12, 31)) - c.acc - erp.asset_impairment_at(p_asset, make_date(c.yr, 12, 31))
  from c
  where c.acc - coalesce((select c2.acc from c c2 where c2.yr = c.yr - 1), 0) > 0
  order by c.yr;
$function$
;
