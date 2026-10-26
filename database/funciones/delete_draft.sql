-- =====================================================================
-- erp.delete_draft · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0070_entries_screen   →   la vigente es la de 0070_entries_screen
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.delete_draft(p_entry uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare e erp.journal_entries;
begin
  select * into e from erp.journal_entries where id = p_entry;
  if not found or not erp.can_write(e.company_id) then raise exception 'No permission to delete entries in this company'; end if;
  if e.status <> 'draft' then raise exception 'Entry % is posted and cannot be deleted. Reverse it instead.', e.entry_no; end if;
  delete from erp.journal_lines where entry_id = p_entry;
  delete from erp.journal_entries where id = p_entry;
end $function$
;
