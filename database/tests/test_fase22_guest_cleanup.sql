-- =====================================================================
-- PRUEBAS FASE 22 · Limpieza automática de invitados (migración 0028)
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

-- Un registrado antiguo, un invitado antiguo con idioma guardado y un invitado reciente
insert into auth.users (id, email, created_at, is_anonymous) values
  ('00000000-0000-0000-0000-0000000000a1', 'owner@test.local', now() - interval '400 days', false),
  ('00000000-0000-0000-0000-0000000000d1', null,               now() - interval '10 days',  true),
  ('00000000-0000-0000-0000-0000000000d2', null,               now() - interval '2 days',   true);
insert into erp.user_settings (user_id, language) values
  ('00000000-0000-0000-0000-0000000000a1', 'es'),
  ('00000000-0000-0000-0000-0000000000d1', 'en'),
  ('00000000-0000-0000-0000-0000000000d2', 'en');

do $$
declare n int;
begin
  -- 1. Desde la web (rol authenticated) no se puede ejecutar
  begin
    set local role authenticated;
    perform erp.cleanup_guests(7);
    raise exception 'FALLO: un usuario de la web ha podido ejecutar la limpieza';
  exception when insufficient_privilege then
    null;
  end;
  reset role;

  -- 2. Días inválidos
  begin
    perform erp.cleanup_guests(0);
    raise exception 'FALLO: aceptó 0 días';
  exception when others then
    assert sqlerrm like 'Guest cleanup needs at least 1 day%', 'mensaje inesperado: ' || sqlerrm;
  end;

  -- 3. Borra solo el invitado de más de 7 días, y su idioma
  n := erp.cleanup_guests(7);
  assert n = 1, 'debía borrar 1 invitado, borró ' || n;
  assert not exists (select 1 from auth.users where id = '00000000-0000-0000-0000-0000000000d1'), 'el invitado antiguo sigue';
  assert not exists (select 1 from erp.user_settings where user_id = '00000000-0000-0000-0000-0000000000d1'), 'quedó su idioma (huérfano)';
  assert exists (select 1 from auth.users where id = '00000000-0000-0000-0000-0000000000d2'), 'borró el invitado reciente';
  assert exists (select 1 from auth.users where id = '00000000-0000-0000-0000-0000000000a1'), 'borró a un usuario registrado';
  assert exists (select 1 from erp.user_settings where user_id = '00000000-0000-0000-0000-0000000000a1'), 'borró el idioma de un registrado';

  -- 4. Segunda ejecución: nada que borrar
  assert erp.cleanup_guests(7) = 0, 'la segunda ejecución debía borrar 0';

  -- 5. Un registrado muy antiguo nunca se borra, aunque se pida 1 día
  perform erp.cleanup_guests(1);
  assert exists (select 1 from auth.users where id = '00000000-0000-0000-0000-0000000000a1'), 'borró a un registrado con 1 día';
  assert (select count(*) from auth.users where is_anonymous) = 0, 'con 1 día, el invitado de 2 días también debía irse';
end $$;

-- 6. La migración se puede volver a ejecutar (sin pg_cron solo avisa)
\i database/migrations/0028_guest_cleanup.sql

\echo 'FASE 22 OK · limpieza de invitados: solo anónimos antiguos, sin huérfanos, protegida y re-ejecutable'
