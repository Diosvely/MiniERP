-- =====================================================================
-- erp.asset_net_value_at · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0046_asset_impairment   →   la vigente es la de 0046_asset_impairment
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.asset_net_value_at(p_asset uuid, p_date date)
 RETURNS numeric
 LANGUAGE sql
 STABLE
AS $function$
  select erp.asset_cost_at(p_asset, p_date)
       - coalesce((select sum(d.amount) from erp.asset_depreciations d where d.asset_id = p_asset and d.period_end <= p_date), 0)
       - erp.asset_impairment_at(p_asset, p_date);
$function$
;
