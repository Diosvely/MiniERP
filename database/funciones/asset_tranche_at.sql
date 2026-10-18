-- =====================================================================
-- erp.asset_tranche_at · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0046_asset_impairment   →   la vigente es la de 0046_asset_impairment
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.asset_tranche_at(p_life integer, p_start date, p_from date, p_d numeric, p_rem numeric, p_date date)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case when p_life - erp.asset_months_at(p_life, p_start, p_from) <= 0 or p_date <= p_from then p_d
              else p_d + least(greatest(p_rem, 0), round(greatest(p_rem, 0)
                     * (erp.asset_months_at(p_life, p_start, p_date) - erp.asset_months_at(p_life, p_start, p_from))
                     / (p_life - erp.asset_months_at(p_life, p_start, p_from)), 2)) end;
$function$
;
