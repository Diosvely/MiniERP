-- =====================================================================
-- erp.accrual_elapsed · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0043_year_end_adjustments   →   la vigente es la de 0043_year_end_adjustments
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.accrual_elapsed(p_total numeric, p_start date, p_months integer, p_date date)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select erp.asset_accumulated_at(p_total, 0, p_months, p_start, p_date);
$function$
;
