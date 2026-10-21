-- =====================================================================
-- erp.equity_bal · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0060_equity_operations 0061_equity_integration   →   la vigente es la de 0061_equity_integration
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.equity_bal(p_company uuid, p_prefix text, p_date date)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'erp', 'public'
AS $function$
  select coalesce(sum(l.credit - l.debit), 0)
  from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id join erp.gl_accounts g on g.id = l.gl_account_id
  join erp.fiscal_years f on f.id = e.fiscal_year_id
  where e.company_id = p_company and e.status = 'posted' and e.entry_type not in ('closing', 'closing_pl')
    and p_date between f.starting_date and f.ending_date and e.posting_date <= p_date and g.account_no like p_prefix || '%';
$function$
;
