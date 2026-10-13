-- =====================================================================
-- 0034 · USO DE LA WEB, SOLO PARA EL PROPIETARIO (v0.31.0)
-- ---------------------------------------------------------------------
-- Para saber cuánta gente prueba la demo cuando se comparte la web (LinkedIn…), cuántos se registran y si vuelven.
-- Sin rastreo ni cookies: se CUENTA lo que ya existe.
--   · Visitantes de la demo = usuarios anónimos de Supabase (el botón "Ver la demo" crea uno por navegador).
--   · Registros = usuarios con correo · Activos = han iniciado sesión en los últimos 7 días.
--   · Empresas creadas, importaciones y consultas a la IA de los últimos 30 días.
-- Todo en cifras agregadas: ni correos ni nombres. Sin contar al propietario (sus pruebas no son tráfico).
--
-- Problema que resuelve de paso: la 0028 BORRA los invitados de más de 7 días (pg_cron, cada noche). Contando solo
-- auth.users, la demo de hace dos semanas habría desaparecido. Ahora erp.cleanup_guests guarda antes cuántos
-- invitados había de cada día en erp.guest_history, y los totales suman las dos cosas.
--
-- erp.web_usage(días): solo responde al propietario (erp.is_owner()); para cualquier otro, error.
-- Como el "Usage analytics" de un SaaS o los informes de uso de Business Central: datos del sistema, no de la empresa.
-- Re-ejecutable.
-- =====================================================================

-- Invitados ya borrados por la limpieza, por día de su visita (hora de Canarias)
create table if not exists erp.guest_history (
  day     date primary key,
  guests  integer not null check (guests >= 0)
);
comment on table erp.guest_history is
  'Demo visitors per day already removed by erp.cleanup_guests (anonymous users are deleted after 7 days).';
alter table erp.guest_history enable row level security;   -- sin políticas: solo las funciones security definer
revoke all on erp.guest_history from public, anon, authenticated;

-- La limpieza de la 0028, igual, pero guardando antes el recuento por día
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

  -- Antes de borrarlos, cuántos había de cada día (para el panel de uso)
  insert into erp.guest_history (day, guests)
  select (u.created_at at time zone 'Atlantic/Canary')::date, count(*)
  from auth.users u where u.id = any (v_ids)
  group by 1
  on conflict (day) do update set guests = erp.guest_history.guests + excluded.guests;

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
revoke execute on function erp.cleanup_guests(int) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- El panel: totales y serie diaria de los últimos N días (7 a 90)
-- ---------------------------------------------------------------------
create or replace function erp.web_usage(p_days int default 30)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_days   int := least(greatest(coalesce(p_days, 30), 7), 90);
  v_today  date := (now() at time zone 'Atlantic/Canary')::date;
  v_from   date := v_today - (v_days - 1);
  v_owners uuid[];
  v_out    jsonb;
begin
  if not erp.is_owner() then raise exception 'Only the application owner can see the web usage'; end if;
  select coalesce(array_agg(user_id), '{}') into v_owners from erp.app_profiles where app_role = 'owner';

  with users as (   -- usuarios que no son el propietario, con su día de alta en hora de Canarias
    select u.is_anonymous, u.last_sign_in_at, (u.created_at at time zone 'Atlantic/Canary')::date as day
    from auth.users u where u.id <> all (v_owners)
  ),
  per_day as (      -- invitados vivos + invitados ya borrados, y registros, por día
    select d::date as day,
           coalesce((select count(*) from users where is_anonymous and users.day = d::date), 0)
             + coalesce((select h.guests from erp.guest_history h where h.day = d::date), 0) as guests,
           (select count(*) from users where not is_anonymous and users.day = d::date) as signups
    from generate_series(v_from, v_today, interval '1 day') d
  )
  select jsonb_build_object(
    'days', v_days,
    'today', v_today,
    'series', (select jsonb_agg(jsonb_build_object('day', day, 'guests', guests, 'signups', signups) order by day) from per_day),
    'guests_today', (select guests from per_day where day = v_today),
    'guests_7d', (select sum(guests) from per_day where day > v_today - 7),
    'guests_period', (select sum(guests) from per_day),
    'guests_total', (select count(*) from users where is_anonymous) + (select coalesce(sum(guests), 0) from erp.guest_history),
    'signups_7d', (select sum(signups) from per_day where day > v_today - 7),
    'signups_period', (select sum(signups) from per_day),
    'users_total', (select count(*) from users where not is_anonymous),
    'active_7d', (select count(*) from users where not is_anonymous and last_sign_in_at > now() - interval '7 days'),
    'companies_period', (select count(*) from erp.companies c
                         where (c.created_at at time zone 'Atlantic/Canary')::date >= v_from and not coalesce(c.created_by = any (v_owners), false)),
    'imports_period', (select count(*) from erp.import_batches b
                       where (b.created_at at time zone 'Atlantic/Canary')::date >= v_from and not coalesce(b.created_by = any (v_owners), false)),
    'ai_calls_period', (select coalesce(sum(a.calls), 0) from erp.ai_usage a
                        where a.used_on >= v_from and a.user_id <> all (v_owners))
  ) into v_out;
  return v_out;
end;
$$;

revoke execute on function erp.web_usage(int) from public, anon;
grant execute on function erp.web_usage(int) to authenticated;
