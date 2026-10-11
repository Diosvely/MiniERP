-- =====================================================================
-- 0028 · LIMPIEZA AUTOMÁTICA DE INVITADOS (v0.28.0)
-- ---------------------------------------------------------------------
-- Cada visita a la demo crea un usuario anónimo en Supabase (auth.users, is_anonymous = true).
-- Desde la v0.28.0 hace falta resolver el CAPTCHA, pero aun así se acumulan: aquí se borran los de más de 7 días.
--   · erp.cleanup_guests(días): borra los invitados antiguos y sus filas en erp (idioma, cuota de IA…).
--     En erp no hay claves foráneas hacia auth.users: sin este paso quedarían filas huérfanas.
--   · Tarea programada con pg_cron (extensión de Supabase): todos los días a las 03:30 UTC.
--     Si pg_cron no está activado (o en las pruebas locales), la migración NO falla: solo avisa.
-- Sustituye a la limpieza manual que proponía el comentario de 0015 (30 días, a mano en el SQL Editor).
--
-- [MANUAL] En Supabase, ANTES de ejecutar esta migración:
--   Database → Extensions → buscar "pg_cron" → Enable.
--   Comprobar la tarea:  select jobname, schedule, command, active from cron.job;
--   Ver ejecuciones:     select status, return_message, start_time from cron.job_run_details order by start_time desc limit 5;
-- Re-ejecutable.
-- =====================================================================

create or replace function erp.cleanup_guests(p_days int default 7)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ids uuid[];
  v_deleted integer;
begin
  if p_days is null or p_days < 1 then
    raise exception 'Guest cleanup needs at least 1 day (got %)', p_days;
  end if;

  -- Solo invitados (anónimos) y solo los antiguos: los usuarios registrados no se tocan nunca
  select array_agg(id) into v_ids
  from auth.users
  where is_anonymous and created_at < now() - make_interval(days => p_days);

  if v_ids is null then
    return 0;
  end if;

  -- Sus filas en erp (un invitado solo puede tener el idioma; el resto, por si acaso)
  delete from erp.user_settings where user_id = any (v_ids);
  delete from erp.ai_usage      where user_id = any (v_ids);
  delete from erp.ai_feedback   where user_id = any (v_ids);
  delete from erp.company_users where user_id = any (v_ids);
  delete from erp.app_profiles  where user_id = any (v_ids);

  -- El usuario (en Supabase, sus sesiones e identidades se borran en cascada)
  delete from auth.users where id = any (v_ids) and is_anonymous;
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

comment on function erp.cleanup_guests(int) is
  'Borra los usuarios invitados (anónimos) de más de N días y sus filas en erp. La ejecuta pg_cron cada día.';

-- Solo la base de datos (pg_cron) o el propietario desde el SQL Editor: nadie desde la web
revoke execute on function erp.cleanup_guests(int) from public, anon, authenticated;

-- Tarea diaria con pg_cron (si está activado)
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'erp-cleanup-guests') then
      perform cron.unschedule('erp-cleanup-guests');
    end if;
    perform cron.schedule('erp-cleanup-guests', '30 3 * * *', 'select erp.cleanup_guests(7)');
    raise notice 'Tarea erp-cleanup-guests programada: cada día a las 03:30 UTC.';
  else
    raise notice 'pg_cron no está activado: la limpieza de invitados no se ha programado. '
                 'Actívalo en Database → Extensions y vuelve a ejecutar esta migración (o ejecuta erp.cleanup_guests(7) a mano).';
  end if;
end $$;
