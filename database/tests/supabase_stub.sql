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
create table if not exists auth.users (id uuid primary key, email text, created_at timestamptz default now());

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
