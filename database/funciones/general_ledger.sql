-- =====================================================================
-- erp.general_ledger · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0029_performance   →   la vigente es la de 0029_performance
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.general_ledger(p_company uuid, p_year integer, p_account text, p_to_date date DEFAULT NULL::date)
 RETURNS TABLE(posting_date date, entry_no integer, document_no text, description text, debit numeric, credit numeric, running_balance numeric)
 LANGUAGE sql
 STABLE
AS $function$
  select e.posting_date,
         e.entry_no,
         e.document_no,
         coalesce(l.description, e.description),
         l.debit,
         l.credit,
         sum(l.debit - l.credit) over (order by e.posting_date, e.entry_no, l.line_no
                                       rows between unbounded preceding and current row)
  from erp.journal_lines   l
  join erp.journal_entries e on e.id = l.entry_id
  where l.gl_account_id = (select a.id from erp.gl_accounts a
                           where a.company_id = p_company and a.account_no = p_account)
    and e.fiscal_year_id = (select fy.id from erp.fiscal_years fy
                            where fy.company_id = p_company and fy.year = p_year)
    and e.status = 'posted'
    and (p_to_date is null or e.posting_date <= p_to_date)
  order by e.posting_date, e.entry_no, l.line_no;
$function$
;
