-- =====================================================================
-- 0085 · Permisos: «lo tuyo, todo; lo de otro, nada» (v0.58.0, paso 284)
-- ---------------------------------------------------------------------
-- Criterio de Diosvely (03-11-2026): el Mini ERP es para aprender haciendo el ciclo completo. Cada persona es dueña
-- absoluta de su información (sin separación de funciones) y nadie entra en la información de otro usuario.
-- La medición del paso 283 (docs/permisos-medicion.md en el Project) encontró tres cosas que no cumplen esas reglas:
--   1. La IA: quien administra su empresa no podía usarla (solo el propietario de la app, el titular de los datos y el
--      creador de una temporal). Ahora la usa, con la cuota diaria que ya había (10 los miembros, 5 los registrados).
--   2. erp.temp_cleanup la podía llamar cualquiera, también un invitado: borraba empresas temporales caducadas de otros.
--      Ahora solo la limpieza programada (sin sesión), el propietario de la app o la propia importación.
--   3. El propietario de la app podía ver quién tiene acceso a la empresa de OTRO usuario y dar o quitar accesos en
--      ella (con otra cuenta suya, entraba); también podía publicar como demo la empresa de otro (la verían todos) y
--      leer las opiniones sobre la IA de cualquier empresa. Ahora todo eso, solo en las empresas que administra.
--   4. erp.fiscal_year_company decía de qué empresa es un ejercicio a cualquiera. Ahora, solo a quien puede leerla.
--   5. 28 funciones se podían ejecutar sin sesión (anon), por el permiso por defecto de PostgreSQL (PUBLIC). No
--      enseñaban datos, pero no tienen por qué estar abiertas.
-- =====================================================================

-- ---------- 1. La IA: también quien administra la empresa ----------
-- La empresa temporal caducada no cuenta (se está borrando). temp_expired con fechas vacías daría NULL: se trata como
-- caducada, para no abrir nada por un NULL.
create or replace function erp.ai_allowed(p_company uuid)
returns boolean language sql stable security definer set search_path = erp, public as $$
  select not erp.is_anonymous() and (
       (erp.is_owner() and erp.can_read(p_company))
    or erp.is_data_owner(p_company)
    or exists (select 1 from erp.companies c
               where c.id = p_company and erp.my_role(c.id) = 'admin'
                 and not (c.temporary and coalesce(erp.temp_expired(c.expires_at, c.last_seen_at), true))));
$$;

-- ---------- 2. La limpieza de temporales: solo quien debe ----------
-- La importación (erp.import_start) se ejecuta con la sesión del usuario: deja una marca en su transacción antes de
-- limpiar. Desde la web no se puede poner esa marca (set_config no está expuesto en la API).
create or replace function erp.temp_cleanup(p_rows int default 50000)
returns int language plpgsql security definer set search_path = erp, public as $$
declare
  v_c     uuid;
  v_done  int := 0;
  v_left  int;
  v_rows  int := least(greatest(p_rows, 0), 50000);
begin
  if auth.uid() is not null and not erp.is_owner()
     and coalesce(current_setting('erp.import_cleanup', true), '') <> 'on' then
    raise exception 'Only the application owner or the scheduled cleanup can clean temporary companies';
  end if;
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

create or replace function erp.import_start(
  p_name text, p_digits int, p_territory text, p_industry text, p_source text, p_file_name text default null)
returns table (company_id uuid, batch_id uuid)
language plpgsql as $$
declare
  v_company uuid;
  v_batch   uuid;
begin
  -- antes de mirar si cabe, se limpia lo caducado (por si pg_cron no está); la marca solo vale para esta llamada
  perform set_config('erp.import_cleanup', 'on', true);
  perform erp.temp_cleanup(20000);
  perform set_config('erp.import_cleanup', '', true);
  insert into erp.companies (name, industry, tax_territory, posting_account_digits, created_by, temporary)
  values (p_name, p_industry, p_territory, p_digits, auth.uid(), not erp.is_trusted())
  returning id into v_company;
  insert into erp.import_batches (company_id, source, file_name)
  values (v_company, p_source, p_file_name)
  returning id into v_batch;
  return query select v_company, v_batch;
end $$;

-- ---------- 3. Los accesos: el propietario de la app, solo en sus empresas ----------
create or replace function erp.can_manage_access(p_company uuid)
returns boolean language sql stable security definer set search_path = erp, public as $$
  -- sin rol, my_role da NULL y «true and NULL» es NULL: un «if not NULL» no entra y dejaría pasar (lo vio la fase 80)
  select erp.is_owner() and coalesce(erp.my_role(p_company) = 'admin', false);
$$;

create or replace function erp.grant_company_access(p_company uuid, p_email text, p_role text, p_data_owner boolean default false)
returns uuid language plpgsql security definer set search_path = erp, public set jit = off as $$
declare v_user uuid;
begin
  if not erp.can_manage_access(p_company) then
    raise exception 'Only the application owner can manage access, and only in the companies they administer';
  end if;
  if p_role not in ('admin', 'accountant', 'viewer') then raise exception 'Unknown role: %', p_role; end if;
  select id into v_user from auth.users where lower(email) = lower(trim(p_email));
  if v_user is null then raise exception 'No registered user with email %', p_email; end if;
  if v_user = auth.uid() then raise exception 'You already have full access'; end if;
  insert into erp.company_users (company_id, user_id, role, data_owner)
  values (p_company, v_user, p_role, coalesce(p_data_owner, false))
  on conflict (company_id, user_id) do update set role = excluded.role, data_owner = excluded.data_owner;
  return v_user;
end $$;

create or replace function erp.revoke_company_access(p_company uuid, p_user uuid)
returns void language plpgsql security definer set search_path = erp, public set jit = off as $$
begin
  if not erp.can_manage_access(p_company) then
    raise exception 'Only the application owner can manage access, and only in the companies they administer';
  end if;
  if p_user = auth.uid() then raise exception 'You cannot remove your own access'; end if;
  delete from erp.company_users where company_id = p_company and user_id = p_user;
end $$;

create or replace function erp.company_access(p_company uuid)
returns table (user_id uuid, email text, role text, data_owner boolean, since timestamptz, ai_calls_today int)
language plpgsql stable security definer set search_path = erp, public set jit = off as $$
begin
  if not erp.can_manage_access(p_company) then
    raise exception 'Only the application owner can manage access, and only in the companies they administer';
  end if;
  return query
  select cu.user_id, u.email::text, cu.role, cu.data_owner, cu.created_at,
         coalesce((select a.calls from erp.ai_usage a where a.user_id = cu.user_id and a.used_on = current_date), 0)
  from erp.company_users cu join auth.users u on u.id = cu.user_id
  where cu.company_id = p_company
  order by cu.created_at;
end $$;

-- Publicar como demo: el titular de los datos, o el propietario de la app en una empresa que administra
create or replace function erp.set_company_demo(p_company uuid, p_demo boolean, p_credit text default null)
returns void language plpgsql security definer set search_path = erp, public set jit = off as $$
begin
  if not (erp.can_manage_access(p_company) or erp.is_data_owner(p_company)) then
    raise exception 'Only the application owner or the data owner can publish a company as demo';
  end if;
  update erp.companies
  set is_demo = p_demo, data_credit = coalesce(nullif(trim(p_credit), ''), data_credit)
  where id = p_company;
end $$;

-- Las opiniones sobre la IA (pregunta y respuesta de esa empresa): las propias, y el propietario las de sus empresas
drop policy if exists read on erp.ai_feedback;
create policy read on erp.ai_feedback for select to authenticated
  using (user_id = auth.uid() or erp.can_manage_access(company_id));

revoke execute on function erp.can_manage_access(uuid) from public, anon;
grant execute on function erp.can_manage_access(uuid) to authenticated;

-- ---------- 4. De qué empresa es un ejercicio: solo para quien la puede leer ----------
-- La usan las reglas de acceso de los periodos contables (can_read / is_admin de una empresa NULL dan false).
create or replace function erp.fiscal_year_company(p_fiscal_year uuid)
returns uuid language sql stable security definer set search_path = erp, public as $$
  select company_id from erp.fiscal_years where id = p_fiscal_year and erp.can_read(company_id);
$$;

-- ---------- 5. Sin sesión, ninguna función ----------
-- Nadie sin sesión usa funciones del ERP (los invitados entran con una sesión anónima, que es «authenticated»).
-- Las funciones de disparador no necesitan el permiso para dispararse: se quitan a todos.
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.prorettype = 'trigger'::regtype as is_trigger,
                  has_function_privilege('public', p.oid, 'execute') as via_public
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'erp' and p.prokind = 'f' loop
    execute format('revoke execute on function %s from public, anon', f.sig);
    if f.is_trigger then
      execute format('revoke execute on function %s from authenticated', f.sig);
    elsif f.via_public then
      -- las que solo tenían el permiso por defecto las siguen usando otras funciones con la sesión del usuario
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
  end loop;
end $$;
