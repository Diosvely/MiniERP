-- =====================================================================
-- erp.account_moves_at · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0082_tax_dashboard   →   la vigente es la de 0082_tax_dashboard
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.account_moves_at(p_company uuid, p_year integer, p_dates date[], p_prefixes text[])
 RETURNS TABLE(at date, prefix text, debit numeric, credit numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  with acc as (
    select g.id, p.prefix
    from erp.gl_accounts g join unnest(p_prefixes) p(prefix) on g.account_no like p.prefix || '%'
    where g.company_id = p_company and erp.can_report(p_company)
  ), per_day as (
    select a.prefix, e.posting_date, sum(l.debit) as dr, sum(l.credit) as cr
    from acc a
    join erp.journal_lines l on l.gl_account_id = a.id and l.company_id = p_company
    join erp.journal_entries e on e.id = l.entry_id
    where e.fiscal_year_id = (select fy.id from erp.fiscal_years fy where fy.company_id = p_company and fy.year = p_year)
      and erp.counts_in_reports(e.status, e.id) and e.entry_type = 'normal'
    group by a.prefix, e.posting_date
  )
  select d.at, p.prefix, coalesce(sum(m.dr), 0), coalesce(sum(m.cr), 0)
  from (select distinct x as at from unnest(p_dates) x) d
  cross join unnest(p_prefixes) p(prefix)
  left join per_day m on m.prefix = p.prefix and (d.at is null or m.posting_date <= d.at)
  group by d.at, p.prefix;
$function$
;
