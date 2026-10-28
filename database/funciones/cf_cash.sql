-- =====================================================================
-- erp.cf_cash · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0022_cash_flow 0074_report_simulation   →   la vigente es la de 0074_report_simulation
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.cf_cash(p_company uuid, p_year integer)
 RETURNS TABLE(opening numeric, closing numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select coalesce(sum(l.debit - l.credit) filter (where e.entry_type = 'opening'), 0),
         coalesce(sum(l.debit - l.credit) filter (where e.entry_type in ('opening', 'normal')), 0)
  from erp.journal_lines l
  join erp.journal_entries e on e.id = l.entry_id and erp.counts_in_reports(e.status, e.id)
  join erp.fiscal_years fy on fy.id = e.fiscal_year_id and fy.year = p_year
  join erp.gl_accounts g on g.id = l.gl_account_id and g.account_no like '57%'
  where e.company_id = p_company;
$function$
;
