-- =====================================================================
-- STUB DE SUPABASE — SOLO PARA PRUEBAS EN LOCAL. NO ejecutar en Supabase.
-- Imita lo mínimo que usan las migraciones: roles anon/authenticated,
-- tabla auth.users y la función auth.uid() (lee el usuario "logueado").
-- =====================================================================
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;

create schema if not exists auth;
create table if not exists auth.users (id uuid primary key, email text, created_at timestamptz default now(),
                                       is_anonymous boolean not null default false);   -- invitados (Supabase)
alter table auth.users add column if not exists last_sign_in_at timestamptz;   -- último inicio de sesión (Supabase)

-- En Supabase, auth.uid() sale del token JWT. Aquí, de una variable de sesión.
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

grant usage on schema auth to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;

-- auth.jwt(): todas las "claims" del token (en Supabase incluye is_anonymous para invitados)
create or replace function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb)
$$;
grant execute on function auth.jwt() to anon, authenticated;

-- v0.60.3 · Solo para las pruebas: dar un acceso a una empresa sin pasar por erp.grant_company_access (que exige ser el
-- propietario de la aplicación). Desde la 0092 una sesión no puede escribir en erp.company_users (SEG-09); las pruebas
-- que preparan «otro usuario con acceso de lectura» lo hacen con esta función, que no existe en Supabase.
create or replace function public.dar_acceso(p_company uuid, p_user uuid, p_role text, p_data_owner boolean default false)
returns void language plpgsql security definer as $$
begin
  insert into erp.company_users (company_id, user_id, role, data_owner) values (p_company, p_user, p_role, p_data_owner);
end $$;
grant execute on function public.dar_acceso(uuid, uuid, text, boolean) to authenticated;
