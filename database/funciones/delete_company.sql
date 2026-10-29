-- =====================================================================
-- erp.delete_company · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0004_journal_entries   →   la vigente es la de 0004_journal_entries
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.delete_company(p_company uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
begin
  if not exists (select 1 from erp.company_users
                 where company_id = p_company and user_id = auth.uid() and role = 'admin') then
    raise exception 'Only the company admin can delete it';
  end if;
  perform set_config('erp.deleting_company', 'on', true);   -- solo dura esta transacción
  delete from erp.companies where id = p_company;
  perform set_config('erp.deleting_company', 'off', true);
end $function$
;
