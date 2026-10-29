-- =====================================================================
-- erp.cf_entry_cash · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0022_cash_flow 0074_report_simulation 0076_performance 0077_large_companies   →   la vigente es la de 0077_large_companies
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.cf_entry_cash(p_company uuid, p_year integer)
 RETURNS TABLE(entry_id uuid, cash numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select l.entry_id, sum(l.debit - l.credit)
  -- v0.52.2: primero los asientos del ejercicio (por su índice) y después sus apuntes
  from (select e.id from erp.journal_entries e
        where e.fiscal_year_id = (select fy.id from erp.fiscal_years fy where fy.company_id = p_company and fy.year = p_year)
          and e.company_id = p_company and erp.counts_in_reports(e.status, e.id) and e.entry_type = 'normal'
        offset 0) e
  join erp.journal_lines l on l.entry_id = e.id
  join erp.gl_accounts g on g.id = l.gl_account_id and g.account_no like '57%'
  group by l.entry_id;
$function$
;
