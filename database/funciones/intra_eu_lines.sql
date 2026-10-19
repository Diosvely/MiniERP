-- =====================================================================
-- erp.intra_eu_lines · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0052_forms_347_349   →   la vigente es la de 0052_forms_347_349
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.intra_eu_lines(p_company uuid)
 RETURNS TABLE(invoice_id uuid, corrected_invoice_id uuid, posting_date date, partner_id uuid, op_key text, amount numeric)
 LANGUAGE sql
 STABLE
AS $function$
  select i.id, i.corrected_invoice_id, i.posting_date, i.partner_id,
         case when i.invoice_type = 'sale' then case when g.account_no ~ '^(705|759)' then 'S' else 'E' end
              else case when g.account_no ~ '^62' then 'I' else 'A' end end,
         sum(l.amount * l.sign)
  from erp.invoices i
  join erp.invoice_lines l on l.invoice_id = i.id
  join erp.tax_codes c on c.code = l.tax_code
  join erp.gl_accounts g on g.id = l.gl_account_id
  where i.company_id = p_company
    and ((i.invoice_type = 'sale' and c.rate_category = 'intra_eu') or (i.invoice_type = 'purchase' and c.rate_category = 'intra_eu_acquisition'))
  group by 1, 2, 3, 4, 5;
$function$
;
