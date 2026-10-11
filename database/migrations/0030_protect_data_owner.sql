-- =====================================================================
-- 0030 · PROTECT DATA OWNER · Solo el propietario de la app nombra titulares de los datos
-- ---------------------------------------------------------------------
-- Fallo (desde 0027): la política "manage" de erp.company_users deja al ADMIN de una empresa editar sus filas.
-- Quien se registra y crea su empresa es admin de ella, así que podía hacer
--   update erp.company_users set data_owner = true where user_id = auth.uid();
-- y con eso usar la IA (cuota diaria) y publicar su empresa como demo con cualquier mención.
-- Regla: una fila con data_owner = true solo la crea o la cambia el owner de la aplicación
-- (en la práctica, con erp.grant_company_access). Los demás pueden quitarla (true → false), nunca ponerla
-- ni trasladarla a otro usuario o empresa.
-- Re-ejecutable.
-- =====================================================================

create or replace function erp.tg_protect_data_owner()
returns trigger language plpgsql security definer set search_path = erp, public as $$
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
end $$;

drop trigger if exists protect_data_owner on erp.company_users;
create trigger protect_data_owner
  before insert or update on erp.company_users
  for each row execute function erp.tg_protect_data_owner();

revoke execute on function erp.tg_protect_data_owner() from public, anon, authenticated;
