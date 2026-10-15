-- =====================================================================
-- erp.cf_entry_cash · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0022_cash_flow   →   la vigente es la de 0022_cash_flow
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.cf_entry_cash(p_company uuid, p_year integer)
 RETURNS TABLE(entry_id uuid, cash numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select l.entry_id, sum(l.debit - l.credit)
  from erp.journal_entries e
  join erp.fiscal_years fy on fy.id = e.fiscal_year_id and fy.year = p_year
  join erp.journal_lines l on l.entry_id = e.id
  join erp.gl_accounts g on g.id = l.gl_account_id and g.account_no like '57%'
  where e.company_id = p_company and e.status = 'posted' and e.entry_type = 'normal'
  group by l.entry_id;
$function$
;
