-- =====================================================================
-- erp.adjust_reverse · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0043_year_end_adjustments   →   la vigente es la de 0043_year_end_adjustments
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.adjust_reverse(p_entry uuid, p_date date, p_reason text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare v int;
begin
  perform set_config('erp.adjust_engine', 'on', true);
  perform set_config('erp.payment_engine', 'on', true);
  v := erp.reverse_entry(p_entry, p_date, p_reason);
  perform set_config('erp.payment_engine', 'off', true);
  perform set_config('erp.adjust_engine', 'off', true);
  return v;
end $function$
;
