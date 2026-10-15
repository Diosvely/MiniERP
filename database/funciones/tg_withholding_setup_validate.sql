-- =====================================================================
-- erp.tg_withholding_setup_validate · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0018_withholding_exempt   →   la vigente es la de 0018_withholding_exempt
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_withholding_setup_validate()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  perform erp.check_tax_account(new.company_id, new.payable_account_id,    '4751', 'withholding payable');
  perform erp.check_tax_account(new.company_id, new.receivable_account_id, '473',  'withholding receivable');
  return new;
end $function$
;
