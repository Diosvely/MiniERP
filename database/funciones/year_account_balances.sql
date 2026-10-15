-- =====================================================================
-- erp.year_account_balances · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0017_year_closing   →   la vigente es la de 0017_year_closing
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.year_account_balances(p_fiscal_year uuid)
 RETURNS TABLE(account_id uuid, account_no text, account_name text, balance numeric)
 LANGUAGE sql
 STABLE
AS $function$
  select g.id, g.account_no, g.name, sum(l.debit - l.credit)
  from erp.journal_lines l
  join erp.journal_entries e on e.id = l.entry_id and e.status = 'posted'
  join erp.gl_accounts g     on g.id = l.gl_account_id
  where e.fiscal_year_id = p_fiscal_year
  group by g.id, g.account_no, g.name
  having sum(l.debit - l.credit) <> 0
  order by g.account_no;
$function$
;
