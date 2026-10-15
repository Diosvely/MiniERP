-- =====================================================================
-- erp.tg_entry_prevent_delete · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0004_journal_entries   →   la vigente es la de 0004_journal_entries
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_entry_prevent_delete()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if old.status = 'posted' and coalesce(current_setting('erp.deleting_company', true), '') <> 'on' then
    raise exception 'Entry % is posted and cannot be deleted. Reverse it instead.', old.entry_no;
  end if;
  return old;
end $function$
;
