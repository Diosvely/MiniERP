-- =====================================================================
-- erp.post_entries · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0070_entries_screen   →   la vigente es la de 0070_entries_screen
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.post_entries(p_company uuid, p_entries uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare r record; v_no int; v_ok jsonb := '[]'::jsonb; v_ko jsonb := '[]'::jsonb;
begin
  if not erp.can_write(p_company) then raise exception 'No permission to post entries in this company'; end if;
  for r in select j.id, j.posting_date from erp.journal_entries j
           where j.company_id = p_company and j.id = any (p_entries) and j.status = 'draft'
           order by j.posting_date, j.created_at loop
    -- lo que se sabe antes (también la cuenta controlada, que el motor comprueba al final de la transacción)
    if erp.draft_problem(r.id) is not null then
      v_ko := v_ko || jsonb_build_object('entry_id', r.id, 'problem', erp.draft_problem(r.id));
      continue;
    end if;
    begin
      v_no := erp.post_entry(r.id);
      v_ok := v_ok || jsonb_build_object('entry_id', r.id, 'entry_no', v_no);
    exception when others then
      v_ko := v_ko || jsonb_build_object('entry_id', r.id, 'error', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('posted', v_ok, 'failed', v_ko);
end $function$
;
