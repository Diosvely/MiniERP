-- =====================================================================
-- erp.tax_moves_at · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0082_tax_dashboard   →   la vigente es la de 0082_tax_dashboard
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tax_moves_at(p_company uuid, p_year integer, p_dates date[])
 RETURNS TABLE(at date, output_tax numeric, input_tax numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  with acc as (
    select a.id, a.side from erp.tax_accounts(p_company, erp.company_tax_type(p_company)) a where erp.can_report(p_company)
  ), lin as (
    select l.entry_id, acc.side, sum(l.debit - l.credit) as amt
    from acc join erp.journal_lines l on l.gl_account_id = acc.id and l.company_id = p_company
    group by l.entry_id, acc.side
  ), ent as (
    select e.id, e.posting_date
    from erp.journal_entries e
    where e.id in (select entry_id from lin)
      and e.fiscal_year_id = (select fy.id from erp.fiscal_years fy where fy.company_id = p_company and fy.year = p_year)
      and erp.counts_in_reports(e.status, e.id) and not erp.is_settlement_entry(e.id)
  ), per_day as (
    select e.posting_date, sum(-l.amt) filter (where l.side = 'output') as o, sum(l.amt) filter (where l.side = 'input') as i
    from ent e join lin l on l.entry_id = e.id
    group by e.posting_date
  )
  select d.at, coalesce(sum(p.o), 0), coalesce(sum(p.i), 0)
  from (select distinct x as at from unnest(p_dates) x) d
  left join per_day p on d.at is null or p.posting_date <= d.at
  group by d.at;
$function$
;
