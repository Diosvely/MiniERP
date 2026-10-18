-- =====================================================================
-- erp.asset_months_at · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0046_asset_impairment   →   la vigente es la de 0046_asset_impairment
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.asset_months_at(p_life integer, p_start date, p_date date)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select erp.asset_accumulated_at(p_life * 1000000.0, 0, p_life, p_start, p_date) / 1000000.0;
$function$
;
