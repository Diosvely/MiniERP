-- =====================================================================
-- erp.net_turnover · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0057_corporate_tax   →   la vigente es la de 0057_corporate_tax
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.net_turnover(p_company uuid, p_fy uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce(sum(l.credit - l.debit), 0)
  from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id join erp.gl_accounts g on g.id = l.gl_account_id
  where e.company_id = p_company and e.fiscal_year_id = p_fy and e.status = 'posted'
    and e.entry_type not in ('closing_pl', 'closing') and g.account_no like '70%';
$function$
;
