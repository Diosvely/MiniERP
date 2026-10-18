-- =====================================================================
-- erp.asset_impairment_at · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0046_asset_impairment   →   la vigente es la de 0046_asset_impairment
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.asset_impairment_at(p_asset uuid, p_date date)
 RETURNS numeric
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce(sum(case e.kind when 'impairment' then e.amount else -e.amount end), 0)
  from erp.asset_events e where e.asset_id = p_asset and e.kind in ('impairment', 'reversal') and e.event_date <= p_date;
$function$
;
