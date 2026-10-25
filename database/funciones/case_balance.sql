-- =====================================================================
-- erp.case_balance · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0066_complete_case   →   la vigente es la de 0066_complete_case
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.case_balance(e uuid, p_prefix text, p_date date)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'erp', 'public'
AS $function$
  select coalesce(sum(l.credit - l.debit), 0) from erp.journal_lines l join erp.journal_entries j on j.id = l.entry_id
  join erp.gl_accounts g on g.id = l.gl_account_id
  where j.company_id = e and j.status = 'posted' and j.posting_date <= p_date and g.account_no like p_prefix || '%';
$function$
;
