-- =====================================================================
-- erp.tg_gl_account_protect · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0099_special_lines_and_account_guard   →   la vigente es la de 0099_special_lines_and_account_guard
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_gl_account_protect()
 RETURNS trigger
 LANGUAGE plpgsql
 SET jit TO 'off'
AS $function$
begin
  if current_user not in ('authenticated', 'anon') then return new; end if;   -- funciones de la base y administrador
  if new.company_id is distinct from old.company_id then
    raise exception 'The company of an account cannot be changed';
  end if;
  if (new.account_no is distinct from old.account_no or new.account_type is distinct from old.account_type)
     and exists (select 1 from erp.journal_lines l where l.gl_account_id = old.id) then
    raise exception 'Account % has journal lines: its number and type cannot be changed', old.account_no;
  end if;
  return new;
end $function$
;
