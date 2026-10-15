-- =====================================================================
-- erp.tg_invoice_protect · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0011_invoices   →   la vigente es la de 0011_invoices
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_invoice_protect()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if coalesce(current_setting('erp.deleting_company', true), '') = 'on' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  if tg_op = 'INSERT' and coalesce(current_setting('erp.invoice_engine', true), '') = 'on' then
    return new;
  end if;
  raise exception 'Invoices are created only with post_invoice() and cannot be changed or deleted: issue a credit memo';
end $function$
;
