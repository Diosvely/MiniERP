-- =====================================================================
-- erp.tg_entry_invoice_reverse · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0011_invoices   →   la vigente es la de 0011_invoices
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_entry_invoice_reverse()
 RETURNS trigger
 LANGUAGE plpgsql
 SET jit TO 'off'
AS $function$
begin
  if new.reversal_of is not null and exists (select 1 from erp.invoices where entry_id = new.reversal_of) then
    raise exception 'This entry belongs to an invoice: issue a credit memo instead of reversing it';
  end if;
  return new;
end $function$
;
