-- =====================================================================
-- 0072 · EMPRESAS TEMPORALES para los registrados · v0.49.0
-- ---------------------------------------------------------------------
-- Diseño validado por Diosvely (diseno-v0.49.0.md, 26-10-2026). La base de datos gratuita de Supabase tiene 500 MB:
--   · Owner y miembros (con perfil puesto por el owner o titulares de datos) → importan como hasta ahora: permanente.
--   · Registrados (colaboradores) → TODO lo que importan va a una EMPRESA TEMPORAL, que no gasta su empresa permanente
--     (esa sigue para crearla a mano o cargar un caso). Una a la vez. Se borra tras 2 h sin actividad o a las 48 h.
--     Tienen IA en ella, con 5 llamadas al día (los miembros, 10).
--   · Invitados de la demo → como hasta ahora (no crean nada).
-- Nadie tiene que avisar de que se va: la web manda un «latido» cada 5 minutos (erp.temp_heartbeat) y una limpieza
-- programada (pg_cron, cada 15 minutos) borra las caducadas por tandas. Al cerrar la pestaña, erp.temp_leave adelanta
-- la caducidad (si hay otra pestaña abierta, su latido la mantiene viva).
-- Topes para no llenar la base de datos (en erp.temp_settings, se cambian con un UPDATE sin migración):
--   20.000 líneas por importación · 200.000 líneas entre todas las temporales · 25 temporales a la vez ·
--   freno si la base de datos pasa de 425 MB → «ahora está lleno, prueba más tarde».
-- Re-ejecutable.
-- =====================================================================

-- ---------- Ajustes (una sola fila) ----------
create table if not exists erp.temp_settings (
  id                   boolean primary key default true check (id),
  idle_minutes         int not null default 120 check (idle_minutes between 10 and 1440),
  max_hours            int not null default 48 check (max_hours between 1 and 720),
  max_lines_per_import int not null default 20000 check (max_lines_per_import > 0),
  max_total_lines      int not null default 200000 check (max_total_lines > 0),
  max_companies        int not null default 25 check (max_companies >= 0),
  max_db_mb            int not null default 425 check (max_db_mb > 0),
  ai_daily_limit       int not null default 5 check (ai_daily_limit >= 0)
);
insert into erp.temp_settings (id) values (true) on conflict (id) do nothing;
comment on table erp.temp_settings is 'Temporary companies of registered users: lifetimes and caps (v0.49.0). Change with UPDATE.';

-- ---------- La empresa temporal ----------
alter table erp.companies add column if not exists temporary boolean not null default false;
alter table erp.companies add column if not exists expires_at timestamptz;
alter table erp.companies add column if not exists last_seen_at timestamptz;
comment on column erp.companies.temporary is 'Temporary company of a registered user (v0.49.0): deleted after inactivity or at expires_at.';
create index if not exists companies_temporary_idx on erp.companies (expires_at) where temporary;

-- ¿Importa en permanente? El owner y los miembros: con perfil puesto por el owner o titulares de datos de una empresa
create or replace function erp.is_trusted()
returns boolean language sql stable security definer set search_path = erp, public as $$
  select not erp.is_anonymous()
     and (erp.is_owner()
          or exists (select 1 from erp.app_profiles where user_id = auth.uid())
          or exists (select 1 from erp.company_users where user_id = auth.uid() and data_owner));
$$;

-- ¿Está caducada? (2 h sin latido o pasado su máximo)
create or replace function erp.temp_expired(p_expires timestamptz, p_last_seen timestamptz)
returns boolean language sql stable as $$
  select now() >= p_expires
      or now() - p_last_seen >= make_interval(mins => (select idle_minutes from erp.temp_settings));
$$;

-- Cuánto ocupan ahora las temporales vivas y si cabe una más
create or replace function erp.temp_capacity()
returns jsonb language sql stable security definer set search_path = erp, public as $$
  with s as (select * from erp.temp_settings),
  live as (select id from erp.companies where temporary and not erp.temp_expired(expires_at, last_seen_at)),
  n as (
    select (select count(*) from live)::int as companies,
           ((select count(*) from erp.journal_lines where company_id in (select id from live))
            + (select count(*) from erp.import_lines where company_id in (select id from live)))::int as lines,
           (pg_database_size(current_database()) / 1048576)::int as db_mb
  )
  select jsonb_build_object('companies', n.companies, 'lines', n.lines, 'db_mb', n.db_mb,
    'max_companies', s.max_companies, 'max_total_lines', s.max_total_lines, 'max_db_mb', s.max_db_mb,
    'full', n.companies >= s.max_companies or n.lines >= s.max_total_lines or n.db_mb >= s.max_db_mb)
  from n, s;
$$;

-- ---------- Reglas al crear y al cambiar una empresa (se añade lo de las temporales) ----------
create or replace function erp.tg_company_rules()
returns trigger language plpgsql security definer set search_path = erp, public as $$
declare
  v_max     int;
  v_created int;
  v_cap     jsonb;
  v_s       erp.temp_settings;
begin
  if auth.uid() is null then
    return new;
  end if;

  if erp.is_anonymous() then
    raise exception 'Guest visitors can only view the demo companies: sign up to create your own';
  end if;

  -- v0.49.0 · Empresas temporales: las fechas las pone la base de datos y nadie la convierte en permanente
  if tg_op = 'UPDATE' then
    if new.temporary is distinct from old.temporary or new.expires_at is distinct from old.expires_at then
      raise exception 'A temporary company cannot be made permanent or extended';
    end if;
  elsif new.temporary then
    select * into v_s from erp.temp_settings;
    if exists (select 1 from erp.companies where created_by = auth.uid() and temporary
               and not erp.temp_expired(expires_at, last_seen_at)) then
      raise exception 'You already have a temporary company: delete it or wait until it expires';
    end if;
    v_cap := erp.temp_capacity();
    if (v_cap->>'full')::boolean then
      raise exception 'Temporary companies are full right now: try again later';
    end if;
    new.expires_at := now() + make_interval(hours => v_s.max_hours);
    new.last_seen_at := now();
    new.is_demo := false;
  else
    new.expires_at := null;
    new.last_seen_at := null;
  end if;

  -- Límite de empresas (las temporales no cuentan)
  if tg_op = 'INSERT' and not new.temporary then
    select max_companies into v_max from erp.my_profile();
    select companies_created into v_created from erp.my_profile();
    if v_max is not null and v_created >= v_max then
      raise exception 'Company limit reached: your account can create % compan%', v_max,
        case when v_max = 1 then 'y' else 'ies' end;
    end if;
  end if;

  if (tg_op = 'INSERT' and new.is_demo)
     or (tg_op = 'UPDATE' and new.is_demo is distinct from old.is_demo) then
    -- el propietario de la aplicación, o el titular de los datos de ESTA empresa (0027); nunca una temporal
    if new.temporary or not (erp.is_owner() or (tg_op = 'UPDATE' and erp.is_data_owner(new.id))) then
      raise exception 'Only the application owner or the data owner can publish a company as demo';
    end if;
  end if;

  return new;
end $$;

-- Las temporales no gastan la empresa permanente
create or replace function erp.my_profile()
returns table (app_role text, max_companies int, companies_created int)
language sql stable security definer set search_path = erp, public as $$
  select case when erp.is_anonymous() then 'guest' else coalesce(p.app_role, 'member') end,
         case when erp.is_anonymous() then 0 when p.user_id is null then 1 else p.max_companies end,
         (select count(*)::int from erp.companies c where c.created_by = auth.uid() and not c.temporary)
  from (select auth.uid() as uid) me
  left join erp.app_profiles p on p.user_id = me.uid;
$$;

-- ---------- Importar: los registrados, siempre en temporal ----------
create or replace function erp.import_start(
  p_name text, p_digits int, p_territory text, p_industry text, p_source text, p_file_name text default null)
returns table (company_id uuid, batch_id uuid)
language plpgsql as $$
declare
  v_company uuid;
  v_batch   uuid;
begin
  perform erp.temp_cleanup(20000);   -- antes de mirar si cabe, se limpia lo caducado (por si pg_cron no está)
  insert into erp.companies (name, industry, tax_territory, posting_account_digits, created_by, temporary)
  values (p_name, p_industry, p_territory, p_digits, auth.uid(), not erp.is_trusted())
  returning id into v_company;
  insert into erp.import_batches (company_id, source, file_name)
  values (v_company, p_source, p_file_name)
  returning id into v_batch;
  return query select v_company, v_batch;
end $$;

-- Un registrado no puede importar en su empresa permanente por otro camino
create or replace function erp.tg_import_batch_temporary()
returns trigger language plpgsql security definer set search_path = erp, public as $$
begin
  if auth.uid() is not null and not erp.is_trusted()
     and not exists (select 1 from erp.companies where id = new.company_id and temporary) then
    raise exception 'Registered users import into a temporary company';
  end if;
  return new;
end $$;
drop trigger if exists import_batch_temporary on erp.import_batches;
create trigger import_batch_temporary before insert on erp.import_batches
  for each row execute function erp.tg_import_batch_temporary();

-- Topes de líneas al subir el fichero: 20.000 por importación y 200.000 entre todas las temporales
create or replace function erp.tg_import_lines_caps()
returns trigger language plpgsql security definer set search_path = erp, public as $$
declare
  v_s   erp.temp_settings;
  v_c   uuid;
  v_n   int;
  v_cap jsonb;
begin
  select * into v_s from erp.temp_settings;
  for v_c in select distinct n.company_id from new_rows n join erp.companies c on c.id = n.company_id where c.temporary loop
    select count(*) into v_n from erp.import_lines where company_id = v_c;
    if v_n > v_s.max_lines_per_import then
      raise exception 'Too many lines for a temporary import: % (maximum %)', v_n, v_s.max_lines_per_import;
    end if;
    v_cap := erp.temp_capacity();
    if (v_cap->>'lines')::int > v_s.max_total_lines then
      raise exception 'Temporary companies are full right now: try again later';
    end if;
  end loop;
  return null;
end $$;
drop trigger if exists import_lines_caps on erp.import_lines;
create trigger import_lines_caps after insert on erp.import_lines
  referencing new table as new_rows for each statement execute function erp.tg_import_lines_caps();

-- ---------- Latido, salida y estado ----------
-- Mientras la app está abierta (cada 5 minutos): mis temporales siguen vivas
create or replace function erp.temp_heartbeat()
returns int language sql security definer set search_path = erp, public as $$
  with u as (
    update erp.companies set last_seen_at = now()
    where created_by = auth.uid() and temporary and not erp.temp_expired(expires_at, last_seen_at)
    returning 1)
  select count(*)::int from u;
$$;

-- Al cerrar la pestaña: se borra en unos 10 minutos si ninguna otra pestaña sigue dando latidos
create or replace function erp.temp_leave()
returns int language sql security definer set search_path = erp, public as $$
  with u as (
    update erp.companies
       set last_seen_at = least(last_seen_at, now() - make_interval(mins => (select idle_minutes - 10 from erp.temp_settings)))
     where created_by = auth.uid() and temporary
    returning 1)
  select count(*)::int from u;
$$;

-- Lo que necesita la web: ¿importo en permanente o en temporal?, mi temporal y si cabe otra
create or replace function erp.temp_status()
returns jsonb language sql stable security definer set search_path = erp, public as $$
  select jsonb_build_object(
    'mode', case when erp.is_anonymous() then 'none' when erp.is_trusted() then 'permanent' else 'temporary' end,
    'idle_minutes', s.idle_minutes, 'max_hours', s.max_hours, 'max_lines_per_import', s.max_lines_per_import,
    'ai_daily_limit', s.ai_daily_limit,
    'company', (select jsonb_build_object('id', c.id, 'name', c.name, 'expires_at', c.expires_at, 'last_seen_at', c.last_seen_at,
                                          'delete_at', least(c.expires_at, c.last_seen_at + make_interval(mins => s.idle_minutes)))
                from erp.companies c where c.created_by = auth.uid() and c.temporary
                  and not erp.temp_expired(c.expires_at, c.last_seen_at)
                order by c.created_at desc limit 1),
    'full', (erp.temp_capacity()->>'full')::boolean)
  from erp.temp_settings s;
$$;

-- ---------- Borrado ----------
-- Una tanda del borrado de una empresa, sin comprobar quién lo pide (lo usan delete_company_step y la limpieza)
create or replace function erp.purge_company_step(p_company uuid, p_batch integer default 5000)
returns integer language plpgsql security definer set search_path = erp, public as $$
declare
  v_ids  uuid[];
  v_left int;
begin
  perform set_config('erp.deleting_company', 'on', true);   -- solo dura esta transacción

  -- Documentos que apuntan a asientos (en la primera tanda; en las siguientes ya no hay nada)
  delete from erp.grants                 where company_id = p_company;   -- v0.44.0 (sus movimientos, en cascada)
  delete from erp.loans                  where company_id = p_company;   -- v0.43.0 (su cuadro y sus movimientos, en cascada)
  delete from erp.equity_operations      where company_id = p_company;   -- v0.42.0
  delete from erp.corporate_tax_returns  where company_id = p_company;   -- v0.41.0 (sus ajustes, en cascada)
  delete from erp.payroll_runs           where company_id = p_company;   -- v0.38.0 (las nóminas de cada empleado, en cascada)
  delete from erp.employees              where company_id = p_company;   -- v0.38.0
  delete from erp.inventory_counts       where company_id = p_company;   -- v0.37.0 (sus líneas, en cascada)
  delete from erp.provision_movements    where company_id = p_company;   -- v0.37.0
  delete from erp.provisions             where company_id = p_company;   -- v0.37.0
  delete from erp.receivable_writeoffs   where company_id = p_company;   -- v0.36.0 (antes que los pagos)
  delete from erp.receivable_impairments where company_id = p_company;   -- v0.36.0
  delete from erp.accruals               where company_id = p_company;   -- v0.36.0
  delete from erp.asset_depreciations where company_id = p_company;
  delete from erp.fixed_assets    where company_id = p_company;
  delete from erp.payments        where company_id = p_company;   -- sus aplicaciones, en cascada
  delete from erp.year_closings   where company_id = p_company;
  delete from erp.pro_rata        where company_id = p_company;
  delete from erp.tax_settlements where company_id = p_company;
  delete from erp.invoices        where company_id = p_company;   -- sus líneas, en cascada

  -- Tanda de asientos (los más recientes primero) + su pareja de anulación
  with b as (
    select id, reversal_of, reversed_by from erp.journal_entries
    where company_id = p_company
    order by posting_date desc, entry_no desc nulls first
    limit greatest(p_batch, 1)
  )
  select array_agg(distinct x) into v_ids
  from (select id from b
        union all select reversal_of from b where reversal_of is not null
        union all select reversed_by from b where reversed_by is not null) s(x);

  if v_ids is not null then
    delete from erp.journal_lines   where entry_id = any (v_ids);
    delete from erp.journal_entries where id = any (v_ids);
  end if;

  select count(*)::int into v_left from erp.journal_entries where company_id = p_company;
  if v_left = 0 then
    delete from erp.import_lines where company_id = p_company;
    delete from erp.companies    where id = p_company;
  end if;

  perform set_config('erp.deleting_company', 'off', true);
  return v_left;
end $$;

-- Borrar una empresa desde la web (v0.26.0): solo su administrador; el borrado, el de siempre
create or replace function erp.delete_company_step(p_company uuid, p_batch integer default 5000)
returns integer language plpgsql security definer set search_path = erp, public as $$
begin
  if not exists (select 1 from erp.company_users
                 where company_id = p_company and user_id = auth.uid() and role = 'admin') then
    raise exception 'Only the company admin can delete it';
  end if;
  return erp.purge_company_step(p_company, p_batch);
end $$;

-- Limpieza: borra por tandas las temporales caducadas, hasta p_rows asientos por llamada. Devuelve las borradas del todo.
create or replace function erp.temp_cleanup(p_rows int default 50000)
returns int language plpgsql security definer set search_path = erp, public as $$
declare
  v_c     uuid;
  v_done  int := 0;
  v_left  int;
  v_rows  int := least(greatest(p_rows, 0), 50000);
begin
  for v_c in select id from erp.companies where temporary and erp.temp_expired(expires_at, last_seen_at) order by expires_at loop
    exit when v_rows <= 0;
    loop
      v_left := erp.purge_company_step(v_c, least(5000, v_rows));
      v_rows := v_rows - 5000;
      exit when v_left = 0 or v_rows <= 0;
    end loop;
    if v_left = 0 then v_done := v_done + 1; end if;
  end loop;
  return v_done;
end $$;

-- ---------- IA: los registrados en su temporal, con 5 al día; los miembros, 10 ----------
create or replace function erp.ai_allowed(p_company uuid)
returns boolean language sql stable security definer set search_path = erp, public as $$
  select (erp.is_owner() and erp.can_read(p_company)) or erp.is_data_owner(p_company)
      or exists (select 1 from erp.companies c where c.id = p_company and c.temporary and c.created_by = auth.uid()
                 and not erp.temp_expired(c.expires_at, c.last_seen_at));
$$;

-- Llamadas al día: el owner, sin límite; el que tenga su límite en el perfil, ese; un miembro, 10; un registrado, 5
create or replace function erp.ai_daily_limit()
returns int language sql stable security definer set search_path = erp, public as $$
  select case when erp.is_owner() then null
              else coalesce((select ai_daily_limit from erp.app_profiles where user_id = auth.uid()),
                            case when erp.is_trusted() then 10 else (select ai_daily_limit from erp.temp_settings) end) end;
$$;

create or replace function erp.ai_status(p_company uuid)
returns jsonb language sql stable security definer set search_path = erp, public as $$
  select jsonb_build_object(
    'allowed', erp.ai_allowed(p_company),
    'used', coalesce((select calls from erp.ai_usage where user_id = auth.uid() and used_on = current_date), 0),
    'limit', erp.ai_daily_limit());
$$;

create or replace function erp.ai_consume(p_company uuid)
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare
  v_limit int;
  v_used  int;
begin
  if not erp.ai_allowed(p_company) then raise exception 'The AI is not enabled for you in this company'; end if;
  insert into erp.ai_usage (user_id, used_on, calls) values (auth.uid(), current_date, 1)
  on conflict (user_id, used_on) do update set calls = erp.ai_usage.calls + 1
  returning calls into v_used;
  if erp.is_owner() then
    return jsonb_build_object('used', v_used, 'limit', null, 'remaining', null);
  end if;
  v_limit := erp.ai_daily_limit();
  if v_used > v_limit then
    raise exception 'Daily AI limit reached (% per day)', v_limit;
  end if;
  return jsonb_build_object('used', v_used, 'limit', v_limit, 'remaining', v_limit - v_used);
end $$;

-- ---------- Vista de la web: si es temporal y cuándo se borra ----------
create or replace view erp.v_my_companies with (security_invoker = true) as
select c.id, c.name, c.vat_registration_no, c.industry, c.tax_territory,
       c.posting_account_digits, c.is_demo, c.created_at,
       erp.my_role(c.id) as my_role,
       c.vat_regime, c.data_credit, erp.is_data_owner(c.id) as is_data_owner, c.control_mode,
       c.case_key, c.case_mode, c.start_date, c.monthly,
       c.temporary, c.expires_at, c.last_seen_at
from erp.companies c
where not (c.temporary and erp.temp_expired(c.expires_at, c.last_seen_at));

-- ---------- Permisos ----------
alter table erp.temp_settings enable row level security;
drop policy if exists read on erp.temp_settings;
create policy read on erp.temp_settings for select to authenticated using (true);
revoke all on erp.temp_settings from anon, public;
grant select on erp.temp_settings to authenticated;
revoke execute on function erp.is_trusted(), erp.temp_expired(timestamptz, timestamptz), erp.temp_capacity(),
  erp.tg_import_batch_temporary(), erp.tg_import_lines_caps(), erp.temp_heartbeat(), erp.temp_leave(), erp.temp_status(),
  erp.purge_company_step(uuid, integer), erp.temp_cleanup(int), erp.ai_daily_limit() from anon, public;
grant execute on function erp.is_trusted(), erp.temp_expired(timestamptz, timestamptz), erp.temp_heartbeat(), erp.temp_leave(),
  erp.temp_status(), erp.ai_daily_limit(), erp.temp_cleanup(int) to authenticated;
-- temp_cleanup: la llama import_start con la sesión del usuario (solo borra lo caducado, con un tope por llamada).
-- purge_company_step y temp_capacity: solo por dentro (y la limpieza programada)

-- ---------- Limpieza programada cada 15 minutos (pg_cron, en Supabase) ----------
-- En Supabase pg_cron viene instalado; si no se puede activar aquí, se activa en Database › Extensions y se vuelve
-- a ejecutar esta migración. Sin pg_cron, la limpieza se hace igualmente al empezar cada importación temporal.
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron')
     and exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    begin
      create extension pg_cron with schema pg_catalog;
    exception when others then
      raise notice 'pg_cron no se pudo activar (%): actívalo en Database › Extensions y vuelve a ejecutar la 0072', sqlerrm;
    end;
  end if;
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'erp-temp-cleanup') then
      perform cron.unschedule('erp-temp-cleanup');
    end if;
    perform cron.schedule('erp-temp-cleanup', '*/15 * * * *', 'select erp.temp_cleanup(50000)');
    raise notice 'Limpieza de empresas temporales programada cada 15 minutos (erp-temp-cleanup)';
  else
    raise notice 'Sin pg_cron: las temporales caducadas se borran al empezar cada importación temporal';
  end if;
end $$;
