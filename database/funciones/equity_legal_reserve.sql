-- =====================================================================
-- erp.equity_legal_reserve · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0060_equity_operations   →   la vigente es la de 0060_equity_operations
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.equity_legal_reserve(p_form text, p_capital numeric, p_reserve numeric, p_profit numeric)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case when p_profit <= 0 then 0
              when p_form = 'sl' and p_capital < 3000
                then greatest(0, least(round(p_profit * 0.20, 2), 3000 - p_capital - p_reserve))
              else greatest(0, least(round(p_profit * 0.10, 2), round(p_capital * 0.20, 2) - p_reserve)) end;
$function$
;
