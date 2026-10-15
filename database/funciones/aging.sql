-- =====================================================================
-- erp.aging · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0035_payments   →   la vigente es la de 0035_payments
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.aging(p_company uuid, p_type text, p_date date DEFAULT NULL::date)
 RETURNS TABLE(partner_id uuid, partner_name text, partner_account_no text, open_invoices integer, not_due numeric, d1_30 numeric, d31_60 numeric, d61_90 numeric, d90_plus numeric, total numeric, account_balance numeric)
 LANGUAGE sql
 STABLE
AS $function$
  with d as (select coalesce(p_date, current_date) as d),
  items as (select * from erp.open_items(p_company, p_date) o where o.invoice_type = p_type and o.pending > 0),
  partners as (
    select bp.id, bp.name, g.account_no, bp.gl_account_id
    from erp.business_partners bp left join erp.gl_accounts g on g.id = bp.gl_account_id
    where bp.company_id = p_company
      and bp.partner_type = any (case p_type when 'purchase' then array['vendor', 'creditor'] else array['customer', 'debtor'] end)
  ),
  balances as (
    select pt.id, coalesce(sum(l.debit - l.credit), 0) * case p_type when 'purchase' then -1 else 1 end as balance
    from partners pt cross join d
    join erp.journal_lines l on l.gl_account_id = pt.gl_account_id
    join erp.journal_entries e on e.id = l.entry_id
    where e.status = 'posted' and e.posting_date <= d.d and e.entry_type <> 'closing'
      and not exists (select 1 from erp.year_closings yc where yc.opening_entry_id = e.id)
    group by pt.id
  )
  select pt.id, pt.name, pt.account_no,
         count(i.invoice_id)::int,
         coalesce(sum(i.pending) filter (where i.days_overdue = 0), 0),
         coalesce(sum(i.pending) filter (where i.days_overdue between 1 and 30), 0),
         coalesce(sum(i.pending) filter (where i.days_overdue between 31 and 60), 0),
         coalesce(sum(i.pending) filter (where i.days_overdue between 61 and 90), 0),
         coalesce(sum(i.pending) filter (where i.days_overdue > 90), 0),
         coalesce(sum(i.pending), 0),
         coalesce(b.balance, 0)
  from partners pt
  left join items i on i.partner_id = pt.id
  left join balances b on b.id = pt.id
  group by pt.id, pt.name, pt.account_no, b.balance
  having coalesce(sum(i.pending), 0) <> 0 or coalesce(b.balance, 0) <> 0
  order by coalesce(sum(i.pending), 0) desc, pt.name;
$function$
;
