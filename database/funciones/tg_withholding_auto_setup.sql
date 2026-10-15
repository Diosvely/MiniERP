-- =====================================================================
-- erp.tg_withholding_auto_setup · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0018_withholding_exempt   →   la vigente es la de 0018_withholding_exempt
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_withholding_auto_setup()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  perform erp.withholding_setup_core(new.company_id);
  return new;
end $function$
;
