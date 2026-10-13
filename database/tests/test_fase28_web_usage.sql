-- =====================================================================
-- PRUEBAS FASE 28 · Uso de la web, solo para el propietario (migración 0034)
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

-- Hoy en Canarias, para fechar los usuarios de prueba a mediodía (sin líos de cambio de día)
create function public.dia(n int) returns timestamptz language sql as $$
  select (((now() at time zone 'Atlantic/Canary')::date - n) + time '12:00') at time zone 'Atlantic/Canary'
$$;

insert into auth.users (id, email, is_anonymous, created_at, last_sign_in_at) values
  ('00000000-0000-0000-0000-0000000000a1', 'owner@test.local', false, public.dia(60), now()),          -- el propietario
  ('00000000-0000-0000-0000-0000000000b1', 'ana@test.local',   false, public.dia(2),  now() - interval '1 day'),
  ('00000000-0000-0000-0000-0000000000b2', 'luis@test.local',  false, public.dia(20), now() - interval '20 days'),
  ('00000000-0000-0000-0000-0000000000c1', null, true, public.dia(0),  now()),   -- invitados de la demo
  ('00000000-0000-0000-0000-0000000000c2', null, true, public.dia(0),  now()),
  ('00000000-0000-0000-0000-0000000000c3', null, true, public.dia(3),  now()),
  ('00000000-0000-0000-0000-0000000000c4', null, true, public.dia(10), now()),   -- se borrarán con la limpieza
  ('00000000-0000-0000-0000-0000000000c5', null, true, public.dia(10), now()),
  ('00000000-0000-0000-0000-0000000000c6', null, true, public.dia(40), now());   -- fuera de los 30 días
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);

-- Empresas: una del propietario (no cuenta) y una de Ana; consultas de IA de Ana y del propietario
insert into erp.companies (name, industry, tax_territory, created_by) values
  ('Del propietario SL', 'services', 'mainland', '00000000-0000-0000-0000-0000000000a1'),
  ('De Ana SL', 'retail', 'canary_islands', '00000000-0000-0000-0000-0000000000b1');
insert into erp.ai_usage (user_id, used_on, calls) values
  ('00000000-0000-0000-0000-0000000000b1', current_date, 4), ('00000000-0000-0000-0000-0000000000a1', current_date, 9);

create table public.ctx (k text primary key, v jsonb);
grant all on public.ctx to authenticated;

set role authenticated;

-- ---------- 1. El propietario ve las cifras ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare u jsonb := erp.web_usage(30);
begin
  insert into public.ctx values ('antes', u);
  assert (u->>'days')::int = 30 and jsonb_array_length(u->'series') = 30, 'serie de 30 días';
  assert (u->>'guests_today')::int = 2, 'invitados hoy: ' || (u->>'guests_today');
  assert (u->>'guests_7d')::int = 3, 'invitados 7 días: ' || (u->>'guests_7d');
  assert (u->>'guests_period')::int = 5, 'invitados 30 días: ' || (u->>'guests_period');
  assert (u->>'guests_total')::int = 6, 'invitados en total';
  assert (u->>'signups_7d')::int = 1 and (u->>'signups_period')::int = 2, 'registros (sin el propietario)';
  assert (u->>'users_total')::int = 2, 'usuarios registrados sin el propietario';
  assert (u->>'active_7d')::int = 1, 'activos: solo Ana';
  assert (u->>'companies_period')::int = 1, 'empresas de otros: ' || (u->>'companies_period');
  assert (u->>'ai_calls_period')::int = 4, 'consultas de IA de otros';
  assert (select (d->>'guests')::int from jsonb_array_elements(u->'series') d where (d->>'day')::date = (u->>'today')::date) = 2,
         'la serie trae el día de hoy';
  assert position('@' in u::text) = 0, 'ni un correo';
  raise notice 'OK  · el propietario ve visitantes, registros, activos y uso, sin contarse a sí mismo';
  assert jsonb_array_length(erp.web_usage(500)->'series') = 90 and jsonb_array_length(erp.web_usage(1)->'series') = 7,
         'entre 7 y 90 días';
  raise notice 'OK  · periodo limitado a 7-90 días';
end $$;

-- ---------- 2. Nadie más ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false) \gset
do $$ begin
  begin
    perform erp.web_usage(30);
    raise exception 'FALLO: un usuario normal ve el uso de la web';
  exception when others then
    assert sqlerrm like 'Only the application owner%', sqlerrm;
  end;
  raise notice 'OK  · un usuario registrado no lo ve';
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false) \gset
do $$ begin
  begin
    perform erp.web_usage(30);
    raise exception 'FALLO: un invitado ve el uso de la web';
  exception when others then
    assert sqlerrm like 'Only the application owner%', sqlerrm;
  end;
  raise notice 'OK  · un invitado de la demo tampoco';
end $$;
do $$ begin
  begin
    perform 1 from erp.guest_history;
    raise exception 'FALLO: se lee el histórico de invitados desde la web';
  exception when insufficient_privilege then
    raise notice 'OK  · el histórico de invitados no se lee desde la web';
  end;
end $$;
reset role;
do $$ begin
  begin
    set local role anon;
    perform erp.web_usage(30);
    raise exception 'FALLO: anon ejecuta web_usage';
  exception when insufficient_privilege then
    raise notice 'OK  · anon no puede ejecutarla';
  end;
end $$;

-- ---------- 3. La limpieza de invitados no hace perder la historia ----------
do $$ begin
  assert erp.cleanup_guests(7) = 3, 'borra los 3 invitados de más de 7 días';
  assert (select count(*) from auth.users where is_anonymous) = 3;
  assert (select guests from erp.guest_history where day = (now() at time zone 'Atlantic/Canary')::date - 10) = 2;
  raise notice 'OK  · la limpieza guarda cuántos invitados había de cada día';
end $$;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare u jsonb := erp.web_usage(30); a jsonb := (select v from public.ctx where k = 'antes');
begin
  assert u->'series' = a->'series', 'la serie diaria es la misma antes y después de la limpieza';
  assert u->>'guests_period' = a->>'guests_period' and u->>'guests_total' = a->>'guests_total', 'y los totales';
  raise notice 'OK  · mismos totales y misma serie después de la limpieza';
end $$;

\echo '✔ FASE 28 OK · uso de la web solo para el propietario'
