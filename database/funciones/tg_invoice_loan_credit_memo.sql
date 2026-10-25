-- =====================================================================
-- erp.tg_invoice_loan_credit_memo · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0063_financing_integration   →   la vigente es la de 0063_financing_integration
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_invoice_loan_credit_memo()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
begin
  if new.corrected_invoice_id is not null and coalesce(current_setting('erp.loan_engine', true), '') <> 'on'
     and exists (select 1 from erp.loan_events v where v.invoice_id = new.corrected_invoice_id) then
    raise exception 'This invoice is a finance lease instalment: undo it from Financing (it issues the credit memo)';
  end if;
  return new;
end $function$
;
