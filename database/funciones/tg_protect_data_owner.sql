-- =====================================================================
-- erp.tg_protect_data_owner · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0030_protect_data_owner   →   la vigente es la de 0030_protect_data_owner
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_protect_data_owner()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
begin
  -- Sin sesión (SQL Editor, pg_cron, migraciones): no se aplica
  if auth.uid() is null or erp.is_owner() then
    return new;
  end if;

  if new.data_owner and (
       tg_op = 'INSERT'
       or not old.data_owner
       or new.user_id    is distinct from old.user_id
       or new.company_id is distinct from old.company_id) then
    raise exception 'Only the application owner can set the data owner of a company';
  end if;

  return new;
end $function$
;
