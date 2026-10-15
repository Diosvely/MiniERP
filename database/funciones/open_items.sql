-- =====================================================================
-- erp.open_items · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0035_payments   →   la vigente es la de 0035_payments
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.open_items(p_company uuid, p_date date DEFAULT NULL::date)
 RETURNS TABLE(invoice_id uuid, invoice_type text, invoice_no text, external_document_no text, partner_id uuid, partner_name text, partner_account_no text, invoice_date date, posting_date date, due_date date, amount_due numeric, credited numeric, paid numeric, pending numeric, status text, days_overdue integer)
 LANGUAGE sql
 STABLE
AS $function$
  with d as (select coalesce(p_date, current_date) as d),
  base as (
    select i.id, i.invoice_type, i.invoice_no, i.external_document_no, i.partner_id, bp.name, g.account_no,
           i.invoice_date, i.posting_date, coalesce(i.due_date, i.invoice_date) as due,
           i.total_amount - i.withholding_amount as due_amount,
           coalesce((select sum(c.total_amount - c.withholding_amount) from erp.invoices c
                     where c.corrected_invoice_id = i.id and c.posting_date <= d.d), 0) as credited,
           coalesce((select sum(a.amount) from erp.payment_applications a
                     join erp.payments p on p.id = a.payment_id
                     where a.invoice_id = i.id and p.payment_date <= d.d
                       and (p.cancel_entry_id is null
                            or (select ce.posting_date from erp.journal_entries ce where ce.id = p.cancel_entry_id) > d.d)), 0) as paid,
           d.d as at
    from erp.invoices i
    cross join d
    join erp.business_partners bp on bp.id = i.partner_id
    left join erp.gl_accounts g on g.id = bp.gl_account_id
    where i.company_id = p_company and i.document_kind = 'invoice' and i.posting_date <= d.d
  )
  select id, invoice_type, invoice_no, external_document_no, partner_id, name, account_no,
         invoice_date, posting_date, due,
         due_amount, credited, paid, due_amount + credited - paid,
         case when due_amount + credited - paid <= 0 then 'paid'
              when paid > 0 or credited <> 0 then 'partial' else 'pending' end,
         case when due_amount + credited - paid > 0 then greatest(at - due, 0) end
  from base;
$function$
;
