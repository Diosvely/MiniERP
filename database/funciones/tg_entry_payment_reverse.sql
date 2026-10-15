-- =====================================================================
-- erp.tg_entry_payment_reverse · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0035_payments   →   la vigente es la de 0035_payments
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_entry_payment_reverse()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.reversal_of is not null and coalesce(current_setting('erp.payment_engine', true), '') <> 'on'
     and exists (select 1 from erp.payments where entry_id = new.reversal_of and cancel_entry_id is null) then
    raise exception 'This entry belongs to a payment: cancel the payment instead';
  end if;
  return new;
end $function$
;
