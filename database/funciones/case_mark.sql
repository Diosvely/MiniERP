-- =====================================================================
-- erp.case_mark · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0067_case_screen   →   la vigente es la de 0067_case_screen
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.case_mark(e uuid, p_n integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
begin
  if not erp.is_admin(e) then raise exception 'No permission: only the company admin can load a case'; end if;
  insert into erp.case_entries (company_id, n, entry_id)
  select e, p_n, j.id from erp.journal_entries j
  where j.company_id = e and not exists (select 1 from erp.case_entries c where c.company_id = e and c.entry_id = j.id);
end $function$
;
