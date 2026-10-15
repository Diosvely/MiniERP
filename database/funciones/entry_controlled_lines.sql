-- =====================================================================
-- erp.entry_controlled_lines · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0036_controlled_accounts   →   la vigente es la de 0036_controlled_accounts
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.entry_controlled_lines(p_entry uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  select erp.controlled_lines(coalesce(jsonb_agg(jsonb_build_object('account_no', g.account_no, 'debit', l.debit, 'credit', l.credit)
                                                 order by l.line_no), '[]'))
  from erp.journal_lines l join erp.gl_accounts g on g.id = l.gl_account_id
  where l.entry_id = p_entry;
$function$
;
