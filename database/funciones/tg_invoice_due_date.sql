-- =====================================================================
-- erp.tg_invoice_due_date · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0035_payments   →   la vigente es la de 0035_payments
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_invoice_due_date()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.due_date is null then
    new.due_date := new.invoice_date + coalesce((select payment_days from erp.business_partners where id = new.partner_id), 0);
  end if;
  return new;
end $function$
;
