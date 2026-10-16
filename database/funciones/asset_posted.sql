-- =====================================================================
-- erp.asset_posted · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0041_fixed_assets   →   la vigente es la de 0041_fixed_assets
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.asset_posted(p_asset uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce(sum(d.amount), 0) from erp.asset_depreciations d where d.asset_id = p_asset;
$function$
;
