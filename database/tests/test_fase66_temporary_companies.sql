-- =====================================================================
-- PRUEBAS FASE 66 · Empresas temporales para los registrados (migración 0072 · v0.49.0)
-- ---------------------------------------------------------------------
-- Diseño validado por Diosvely (diseno-v0.49.0.md):
--   · Owner y miembros importan en permanente; un registrado, siempre en una empresa temporal que no gasta su empresa
--     permanente. Una temporal a la vez; nadie la vuelve permanente ni la alarga.
--   · Se borra tras 2 h sin latido o a las 48 h (la limpieza borra por tandas, con sus asientos).
--   · Topes: 20.000 líneas por importación, 200.000 entre todas, 25 temporales y 425 MB → «está lleno».
--   · IA: el registrado, en su temporal y con 5 al día; un miembro, 10.
--   · Los invitados de la demo, como antes.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'owner@test.local'),
  ('00000000-0000-0000-0000-0000000000b2', 'registrado@test.local'),
  ('00000000-0000-0000-0000-0000000000c3', 'otro@test.local'),
  ('00000000-0000-0000-0000-0000000000d4', 'miembro@test.local'),
  ('00000000-0000-0000-0000-0000000000e5', 'invitado@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values
  ('00000000-0000-0000-0000-0000000000a1', 'owner', null),
  ('00000000-0000-0000-0000-0000000000d4', 'member', 3);
create table public.ctx (k text primary key, e uuid);
grant all on public.ctx to authenticated;

create or replace function public.falla(sql text, texto text) returns boolean language plpgsql as $$
begin
  execute sql;
  return false;
exception when others then
  if sqlerrm ilike '%' || texto || '%' then return true; end if;
  raise notice 'error inesperado: %', sqlerrm;
  return false;
end $$;
-- Importa un diario pequeño (un año, dos asientos) y devuelve la empresa
create or replace function public.importar(nombre text) returns uuid language plpgsql as $$
declare e uuid; b uuid; m record; r jsonb;
begin
  select company_id, batch_id into e, b from erp.import_start(nombre, 8, 'canary_islands', 'services', 'dynamics', 'x.xlsx');
  insert into erp.import_lines (batch_id, company_id, row_no, entry_date, entry_ref, entry_type, account_no, account_name, debit, credit)
  values (b, e, 1, '2025-03-10', '1', 'normal', '43000001', 'Cliente', 1070, 0),
         (b, e, 2, '2025-03-10', '1', 'normal', '70000000', null, 0, 1000),
         (b, e, 3, '2025-03-10', '1', 'normal', '47700000', null, 0, 70),
         (b, e, 4, '2025-04-02', '2', 'normal', '62900000', null, 300, 0),
         (b, e, 5, '2025-04-02', '2', 'normal', '57200000', null, 0, 300);
  for m in select * from erp.import_prepare(b) loop perform erp.import_post_month(b, m.year, m.month); end loop;
  loop r := erp.import_finish(b); exit when (r->>'done')::boolean; end loop;
  return e;
end $$;
create or replace function public.como(u text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000' || u, false),
         set_config('request.jwt.claims', '{}', false);
$$;
grant execute on function public.falla(text, text), public.importar(text), public.como(text) to authenticated;

set role authenticated;

-- ---------- Quién importa en permanente y quién en temporal ----------
select public.como('a1');
do $$
declare e uuid;
begin
  assert (erp.temp_status()->>'mode') = 'permanent', 'el owner importa en permanente';
  e := public.importar('Del owner SL');
  assert not (select temporary from erp.companies where id = e), 'la del owner es permanente';
  assert (select expires_at from erp.companies where id = e) is null, 'sin caducidad';
  insert into public.ctx values ('owner', e);
  raise notice 'OK  · el owner importa en permanente';
end $$;

select public.como('d4');
do $$
declare e uuid;
begin
  assert (erp.temp_status()->>'mode') = 'permanent', 'un miembro (con perfil del owner) importa en permanente';
  e := public.importar('Del miembro SL');
  assert not (select temporary from erp.companies where id = e), 'la del miembro es permanente';
  raise notice 'OK  · un miembro importa en permanente';
end $$;

select public.como('b2');
do $$
declare e uuid; s jsonb;
begin
  assert (erp.temp_status()->>'mode') = 'temporary', 'un registrado importa en temporal';
  e := public.importar('Mi prueba SL');
  assert (select temporary from erp.companies where id = e), 'la del registrado es temporal';
  assert (select expires_at - created_at from erp.companies where id = e) between interval '47 hours 59 minutes' and interval '48 hours 1 minute', 'caduca a las 48 h';
  assert (select count(*) from erp.journal_lines where company_id = e) = 5, 'con sus asientos';
  assert (select companies_created from erp.my_profile()) = 0, 'no gasta su empresa permanente';
  s := erp.temp_status();
  assert (s->'company'->>'id')::uuid = e, 'temp_status enseña mi temporal';
  assert (s->'company'->>'delete_at')::timestamptz between now() + interval '119 minutes' and now() + interval '121 minutes', 'se borra en 2 h sin latido';
  assert (select temporary from erp.v_my_companies where id = e), 'la web sabe que es temporal';
  insert into public.ctx values ('temp', e);
  raise notice 'OK  · un registrado importa en una temporal que caduca a las 48 h y no gasta su empresa';
end $$;

do $$
declare e uuid := (select c.e from public.ctx c where c.k = 'temp'); p uuid;
begin
  assert public.falla($q$select public.importar('Otra SL')$q$, 'already have a temporary company'), 'una temporal a la vez';
  assert public.falla(format('update erp.companies set temporary = false where id = %L', e), 'cannot be made permanent'), 'no se vuelve permanente';
  assert public.falla(format('update erp.companies set expires_at = now() + interval ''30 days'' where id = %L', e), 'cannot be made permanent'), 'ni se alarga';
  assert public.falla(format('update erp.companies set is_demo = true where id = %L', e), 'publish'), 'ni se publica como demo';
  -- Su empresa permanente la sigue teniendo, pero no puede importar en ella
  insert into erp.companies (name, industry, tax_territory, created_by) values ('Mi empresa SL', 'services', 'canary_islands', auth.uid()) returning id into p;
  assert not (select temporary from erp.companies where id = p), 'la creada a mano es permanente';
  assert public.falla(format('insert into erp.import_batches (company_id, source) values (%L, %L)', p, 'template'), 'temporary company'),
    'en la permanente no se importa';
  assert public.falla($q$insert into erp.companies (name, industry, tax_territory, created_by) values ('Segunda SL', 'services', 'mainland', auth.uid())$q$, 'Company limit'),
    'y sigue con su límite de una permanente';
  raise notice 'OK  · una temporal a la vez, sin volverla permanente; la permanente, sin importar';
end $$;

-- ---------- IA ----------
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 'temp'); p uuid := (select id from erp.companies where name = 'Mi empresa SL');
begin
  assert erp.ai_allowed(e), 'IA en su temporal';
  assert not erp.ai_allowed(p), 'no en su empresa permanente (como antes)';
  assert (erp.ai_status(e)->>'limit')::int = 5, '5 al día';
  for i in 1..5 loop perform erp.ai_consume(e); end loop;
  assert public.falla(format('select erp.ai_consume(%L)', e), 'Daily AI limit reached (5 per day)'), 'la sexta, no';
  raise notice 'OK  · el registrado tiene IA en su temporal, con 5 al día';
end $$;
select public.como('d4');
do $$
begin
  assert erp.ai_daily_limit() = 10, 'un miembro, 10 al día';
  raise notice 'OK  · un miembro, 10 al día';
end $$;
select public.como('a1');
do $$ begin assert erp.ai_daily_limit() is null, 'el owner, sin límite'; raise notice 'OK  · el owner, sin límite'; end $$;

-- ---------- Latido, salida y limpieza ----------
select public.como('b2');
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 'temp');
begin
  assert erp.temp_heartbeat() = 1, 'el latido mantiene viva mi temporal';
  assert erp.temp_leave() = 1, 'al cerrar la pestaña';
  assert (erp.temp_status()->'company'->>'delete_at')::timestamptz <= now() + interval '10 minutes 1 second', 'se borrará en unos 10 minutos';
  assert erp.temp_heartbeat() = 1, 'pero si otra pestaña sigue abierta, su latido la mantiene';
  assert (erp.temp_status()->'company'->>'delete_at')::timestamptz > now() + interval '119 minutes', 'otra vez 2 h';
  raise notice 'OK  · latido, salida (unos 10 minutos) y otra pestaña que la mantiene viva';
end $$;
-- Pasan 2 h sin latido (se simula desde el SQL Editor)
reset role;
update erp.companies set last_seen_at = now() - interval '121 minutes' where id = (select e from public.ctx where k = 'temp');
set role authenticated;
select public.como('b2');
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 'temp');
begin
  assert not exists (select 1 from erp.v_my_companies where id = e), 'caducada: ya no sale en la lista';
  assert not erp.ai_allowed(e), 'ni tiene IA';
  assert (erp.temp_status()->'company') = 'null'::jsonb, 'ya no tengo temporal';
  raise notice 'OK  · tras 2 h sin latido, caducada';
end $$;
-- La limpieza programada (como pg_cron: sin sesión)
reset role;
select set_config('request.jwt.claim.sub', '', false) \gset
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 'temp'); o uuid := (select c.e from public.ctx c where c.k = 'owner');
begin
  assert erp.temp_cleanup() = 1, 'la limpieza borra la caducada';
  assert not exists (select 1 from erp.companies where id = e), 'la empresa';
  assert not exists (select 1 from erp.journal_lines where company_id = e), 'sus líneas';
  assert not exists (select 1 from erp.journal_entries where company_id = e), 'sus asientos';
  assert not exists (select 1 from erp.gl_accounts where company_id = e), 'sus cuentas';
  assert exists (select 1 from erp.journal_lines where company_id = o), 'y no toca las permanentes';
  assert erp.temp_cleanup() = 0, 'la segunda vez no hay nada';
  raise notice 'OK  · la limpieza borra la caducada (2 h sin latido) con sus asientos y no toca las permanentes';
end $$;

-- ---------- Topes ----------
set role authenticated;
select public.como('b2');
do $$
begin
  perform public.importar('Otra vez SL');   -- tras el borrado, puede volver a importar
  raise notice 'OK  · tras el borrado, puede volver a importar';
end $$;
-- Pasadas las 48 h se borra aunque siga dando latidos
reset role;
select set_config('request.jwt.claim.sub', '', false) \gset
update erp.companies set expires_at = now() - interval '1 minute', last_seen_at = now() where name = 'Otra vez SL';
do $$
begin
  assert erp.temp_cleanup() = 1, 'pasadas las 48 h, también';
  assert not exists (select 1 from erp.companies where name = 'Otra vez SL'), 'borrada';
  raise notice 'OK  · pasadas las 48 h se borra aunque haya latido';
end $$;
reset role;
update erp.temp_settings set max_lines_per_import = 4;
set role authenticated;
select public.como('c3');
do $$
begin
  assert public.falla($q$select public.importar('Grande SL')$q$, 'Too many lines for a temporary import: 5 (maximum 4)'), 'más de las líneas por importación';
  raise notice 'OK  · tope de líneas por importación';
end $$;
reset role;
update erp.temp_settings set max_lines_per_import = 20000, max_companies = 1;
set role authenticated;
select public.como('b2');
select public.importar('Viva SL') \gset
select public.como('c3');
do $$
begin
  assert (erp.temp_status()->>'full')::boolean, 'lleno';
  assert public.falla($q$select public.importar('Llena SL')$q$, 'full right now'), 'con 25 (aquí 1) temporales, está lleno';
  raise notice 'OK  · tope de temporales a la vez';
end $$;
reset role;
update erp.temp_settings set max_companies = 25, max_total_lines = 5;
set role authenticated;
select public.como('c3');
do $$
begin
  assert public.falla($q$select public.importar('Llena SL')$q$, 'full right now'), 'con el presupuesto de líneas gastado, está lleno';
  raise notice 'OK  · presupuesto de líneas entre todas las temporales';
end $$;
reset role;
update erp.temp_settings set max_total_lines = 200000, max_db_mb = 1;
set role authenticated;
select public.como('c3');
do $$
begin
  assert public.falla($q$select public.importar('Llena SL')$q$, 'full right now'), 'con la base de datos por encima del freno, está lleno';
  raise notice 'OK  · freno por el tamaño de la base de datos';
end $$;
reset role;
update erp.temp_settings set max_db_mb = 425;
do $$
begin
  assert (select row(idle_minutes, max_hours, max_lines_per_import, max_total_lines, max_companies, max_db_mb, ai_daily_limit)::text
            from erp.temp_settings) = '(120,48,20000,200000,25,425,5)', 'los ajustes validados';
  raise notice 'OK  · ajustes: 2 h, 48 h, 20.000 líneas, 200.000 en total, 25 temporales, 425 MB y 5 de IA';
end $$;

-- ---------- Permisos ----------
set role authenticated;
select public.como('e5');
select set_config('request.jwt.claims', '{"is_anonymous": true}', false) \gset
do $$
begin
  assert (erp.temp_status()->>'mode') = 'none', 'el invitado no importa';
  assert public.falla($q$select public.importar('Invitado SL')$q$, 'Guest visitors'), 'como antes';
  raise notice 'OK  · el invitado de la demo, como antes';
end $$;
select public.como('c3');
do $$
declare o uuid := (select c.e from public.ctx c where c.k = 'owner');
begin
  assert public.falla($q$update erp.temp_settings set max_companies = 999$q$, 'permission denied'), 'nadie cambia los ajustes desde la web';
  assert public.falla($q$select erp.purge_company_step(gen_random_uuid())$q$, 'permission denied'), 'el borrado interno no se llama desde la web';
  assert public.falla(format('select erp.delete_company_step(%L)', o), 'Only the company admin'), 'borrar una empresa ajena, como antes';
  raise notice 'OK  · ajustes y borrado interno fuera del alcance de la web';
end $$;
reset role;
