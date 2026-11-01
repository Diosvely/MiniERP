-- =====================================================================
-- erp.cash_moves_at · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0081_treasury_dashboard   →   la vigente es la de 0081_treasury_dashboard
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.cash_moves_at(p_company uuid, p_year integer, p_dates date[])
 RETURNS TABLE(at date, cash_in numeric, cash_out numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  with ent as (
    select e.id, e.posting_date
    from erp.journal_entries e
    where e.fiscal_year_id = (select fy.id from erp.fiscal_years fy where fy.company_id = p_company and fy.year = p_year)
      and e.company_id = p_company and erp.counts_in_reports(e.status, e.id)
      and e.entry_type = 'normal' and erp.can_report(p_company)
    offset 0
  ), per_entry as (
    select e.posting_date, sum(l.debit - l.credit) as cash
    from ent e
    join erp.journal_lines l on l.entry_id = e.id and l.company_id = p_company
    join erp.gl_accounts g on g.id = l.gl_account_id and g.account_no like '57%'
    group by e.id, e.posting_date
  ), per_day as (
    select posting_date, sum(greatest(cash, 0)) as cin, sum(greatest(-cash, 0)) as cout
    from per_entry group by posting_date
  )
  select d.at, coalesce(sum(p.cin), 0), coalesce(sum(p.cout), 0)
  from (select distinct x as at from unnest(p_dates) x) d
  left join per_day p on d.at is null or p.posting_date <= d.at
  group by d.at;
$function$
;
