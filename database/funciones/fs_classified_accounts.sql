-- =====================================================================
-- erp.fs_classified_accounts · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0016_financial_statements 0017_year_closing 0074_report_simulation   →   la vigente es la de 0074_report_simulation
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.fs_classified_accounts(p_company uuid, p_year integer, p_statement text, p_to_date date DEFAULT NULL::date)
 RETURNS TABLE(account_no text, account_name text, account_name_en text, balance numeric, line_code text, amount numeric)
 LANGUAGE sql
 STABLE
AS $function$
  with acc as (
    select g.account_no, g.name, g.name_en, sum(l.debit - l.credit) as bal
    from erp.journal_lines l
    join erp.journal_entries e on e.id = l.entry_id and erp.counts_in_reports(e.status, e.id)
                              and e.entry_type not in ('closing_pl', 'closing')
    join erp.fiscal_years fy   on fy.id = e.fiscal_year_id and fy.year = p_year
    join erp.gl_accounts g     on g.id = l.gl_account_id
    where e.company_id = p_company
      and (p_to_date is null or e.posting_date <= p_to_date)
      and (p_statement = 'balance' or left(g.account_no, 1) in ('6', '7'))
    group by g.account_no, g.name, g.name_en
    having sum(l.debit - l.credit) <> 0
  )
  select a.account_no, a.name, a.name_en, a.bal,
         m.line,
         a.bal * case fl.side when 'debit' then 1 else -1 end
  from acc a
  cross join lateral (
    select case when a.bal >= 0 then fm.debit_line else fm.credit_line end as line
    from erp.fs_mapping fm
    where fm.statement = p_statement and a.account_no like fm.prefix || '%'
    order by length(fm.prefix) desc limit 1) m
  join erp.fs_lines fl on fl.statement = p_statement and fl.code = m.line;
$function$
;
