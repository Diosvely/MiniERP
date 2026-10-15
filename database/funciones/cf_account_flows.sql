-- =====================================================================
-- erp.cf_account_flows · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0022_cash_flow   →   la vigente es la de 0022_cash_flow
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.cf_account_flows(p_company uuid, p_year integer)
 RETURNS TABLE(account_no text, account_name text, account_name_en text, flow numeric, home_line text, adjust_line text, direct_line text, in_result boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select a.account_no, a.name, a.name_en, a.flow, m.home_line, m.adjust_line, m.direct_line,
         left(a.account_no, 1) in ('6', '7') and m.home_line <> 'IA4d'
  from (
    select g.account_no, g.name, g.name_en, -sum(l.debit - l.credit) as flow
    from erp.journal_lines l
    join erp.journal_entries e on e.id = l.entry_id and e.status = 'posted' and e.entry_type = 'normal'
    join erp.fiscal_years fy on fy.id = e.fiscal_year_id and fy.year = p_year
    join erp.gl_accounts g on g.id = l.gl_account_id
    where e.company_id = p_company and g.account_no not like '57%'
    group by g.account_no, g.name, g.name_en
    having sum(l.debit - l.credit) <> 0) a
  cross join lateral erp.cf_account_map(a.account_no) m;
$function$
;
