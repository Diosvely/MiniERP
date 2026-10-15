-- =====================================================================
-- erp.tg_tax_settlement_validate · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0010_tax_setup   →   la vigente es la de 0010_tax_setup
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_tax_settlement_validate()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  perform erp.check_tax_account(new.company_id, new.payable_account_id,    '4750', 'payable');
  perform erp.check_tax_account(new.company_id, new.receivable_account_id, '4700', 'receivable');
  return new;
end $function$
;
