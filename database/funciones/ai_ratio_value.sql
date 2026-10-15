-- =====================================================================
-- erp.ai_ratio_value · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0024_ai_context   →   la vigente es la de 0024_ai_context
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.ai_ratio_value(p_value numeric, p_unit text)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case p_unit when 'pct' then round(p_value * 100, 1) when 'days' then round(p_value, 0)
                     else round(p_value, 2) end;
$function$
;
