-- =====================================================================
-- erp.adjust_finish · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0043_year_end_adjustments   →   la vigente es la de 0043_year_end_adjustments
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.adjust_finish(p_entry uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare v int;
begin
  perform set_config('erp.adjust_engine', 'on', true);
  v := erp.post_entry(p_entry);
  perform set_config('erp.adjust_engine', 'off', true);
  return v;
end $function$
;
