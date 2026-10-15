-- =====================================================================
-- erp.preview_invoice · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0011_invoices   →   la vigente es la de 0011_invoices
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.preview_invoice(p jsonb)
 RETURNS TABLE(line_no integer, account_no text, account_name text, debit numeric, credit numeric, tax_code text, tax_base numeric, line_role text)
 LANGUAGE sql
AS $function$
  select e.line_no, e.account_no, e.account_name, e.debit, e.credit,
         case when e.line_role = 'base' then null else e.tax_code end, e.tax_base, e.line_role
  from erp.invoice_entry_lines(p) e
  order by e.line_no nulls last;
$function$
;
