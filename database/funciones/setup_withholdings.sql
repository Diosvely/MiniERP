-- =====================================================================
-- erp.setup_withholdings · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0018_withholding_exempt   →   la vigente es la de 0018_withholding_exempt
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.setup_withholdings(p_company uuid)
 RETURNS TABLE(withholding_code text, account_role text, account_no text, status text)
 LANGUAGE plpgsql
AS $function$
begin
  if not erp.is_admin(p_company) then
    raise exception 'Only the company admin can configure withholdings';
  end if;
  return query select * from erp.withholding_setup_core(p_company);
end $function$
;
