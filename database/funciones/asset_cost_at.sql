-- =====================================================================
-- erp.asset_cost_at · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0046_asset_impairment   →   la vigente es la de 0046_asset_impairment
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.asset_cost_at(p_asset uuid, p_date date)
 RETURNS numeric
 LANGUAGE sql
 STABLE
AS $function$
  select a.cost - coalesce((select sum(e.amount) from erp.asset_events e
                            where e.asset_id = a.id and e.kind = 'cost_adjustment' and e.event_date > p_date), 0)
  from erp.fixed_assets a where a.id = p_asset;
$function$
;
