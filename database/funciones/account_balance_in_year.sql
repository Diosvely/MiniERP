-- =====================================================================
-- erp.account_balance_in_year · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0047_inventory_closing   →   la vigente es la de 0047_inventory_closing
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.account_balance_in_year(p_account uuid, p_fy uuid, p_date date)
 RETURNS numeric
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce(sum(l.debit - l.credit), 0) from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id
  where l.gl_account_id = p_account and e.fiscal_year_id = p_fy and e.status = 'posted' and e.entry_type <> 'closing'
    and e.posting_date <= p_date;
$function$
;
