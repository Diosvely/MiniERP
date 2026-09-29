-- =====================================================================
-- 0006 · SEGURIDAD: permisos y Row Level Security (multiusuario)
-- ---------------------------------------------------------------------
-- Idea: cada fila lleva empresa_id; un usuario solo ve/toca las empresas
-- en las que figura en usuarios_empresa, según su rol:
--   lectura   → consultar
--   contable  → + cuentas, terceros y asientos
--   admin     → + ejercicios, periodos, usuarios y la propia empresa
-- En SAP esto serían objetos de autorización por sociedad; en BC, permission sets.
-- =====================================================================

-- Rol del usuario actual en una empresa (null si no tiene acceso).
-- security definer: consulta usuarios_empresa sin quedar atrapada en su propia RLS.
create or replace function conta.mi_rol(p_empresa uuid)
returns text language sql stable security definer set search_path = conta, public as $$
  select rol from conta.usuarios_empresa where empresa_id = p_empresa and user_id = auth.uid();
$$;

create or replace function conta.puede_leer(p_empresa uuid)
returns boolean language sql stable as $$ select conta.mi_rol(p_empresa) is not null $$;

create or replace function conta.puede_escribir(p_empresa uuid)
returns boolean language sql stable as $$ select conta.mi_rol(p_empresa) in ('admin', 'contable') $$;

create or replace function conta.es_admin(p_empresa uuid)
returns boolean language sql stable as $$ select conta.mi_rol(p_empresa) = 'admin' $$;

create or replace function conta.empresa_de_ejercicio(p_ejercicio uuid)
returns uuid language sql stable security definer set search_path = conta, public as $$
  select empresa_id from conta.ejercicios where id = p_ejercicio;
$$;

-- ---------------------------------------------------------------------
-- Activar RLS en todas las tablas
-- ---------------------------------------------------------------------
alter table conta.empresas         enable row level security;
alter table conta.usuarios_empresa enable row level security;
alter table conta.ejercicios       enable row level security;
alter table conta.periodos         enable row level security;
alter table conta.pgc_plantilla    enable row level security;
alter table conta.cuentas          enable row level security;
alter table conta.terceros         enable row level security;
alter table conta.impuestos_tipos  enable row level security;
alter table conta.asientos         enable row level security;
alter table conta.apuntes          enable row level security;

-- Catálogos globales: todos los usuarios con sesión los leen, nadie los modifica desde la web
create policy leer on conta.pgc_plantilla   for select to authenticated using (true);
create policy leer on conta.impuestos_tipos for select to authenticated using (true);

-- Empresas (creado_por en el SELECT: permite leer la fila recién creada en el mismo INSERT … RETURNING)
create policy leer     on conta.empresas for select to authenticated
  using (conta.puede_leer(id) or creado_por = auth.uid());
create policy crear    on conta.empresas for insert to authenticated with check (creado_por = auth.uid());
create policy editar   on conta.empresas for update to authenticated
  using (conta.es_admin(id)) with check (conta.es_admin(id));
create policy borrar   on conta.empresas for delete to authenticated using (conta.es_admin(id));

-- Usuarios por empresa: los miembros ven al equipo; solo el admin lo gestiona
create policy leer     on conta.usuarios_empresa for select to authenticated using (conta.puede_leer(empresa_id));
create policy gestionar on conta.usuarios_empresa for all to authenticated
  using (conta.es_admin(empresa_id)) with check (conta.es_admin(empresa_id));

-- Ejercicios y periodos: leer miembros, gestionar admin
create policy leer      on conta.ejercicios for select to authenticated using (conta.puede_leer(empresa_id));
create policy gestionar on conta.ejercicios for all to authenticated
  using (conta.es_admin(empresa_id)) with check (conta.es_admin(empresa_id));

create policy leer      on conta.periodos for select to authenticated
  using (conta.puede_leer(conta.empresa_de_ejercicio(ejercicio_id)));
create policy gestionar on conta.periodos for all to authenticated
  using (conta.es_admin(conta.empresa_de_ejercicio(ejercicio_id)))
  with check (conta.es_admin(conta.empresa_de_ejercicio(ejercicio_id)));

-- Cuentas, terceros, asientos y apuntes: leer miembros, escribir admin y contable
create policy leer     on conta.cuentas  for select to authenticated using (conta.puede_leer(empresa_id));
create policy escribir on conta.cuentas  for all to authenticated
  using (conta.puede_escribir(empresa_id)) with check (conta.puede_escribir(empresa_id));

create policy leer     on conta.terceros for select to authenticated using (conta.puede_leer(empresa_id));
create policy escribir on conta.terceros for all to authenticated
  using (conta.puede_escribir(empresa_id)) with check (conta.puede_escribir(empresa_id));

create policy leer     on conta.asientos for select to authenticated using (conta.puede_leer(empresa_id));
create policy escribir on conta.asientos for all to authenticated
  using (conta.puede_escribir(empresa_id)) with check (conta.puede_escribir(empresa_id));

create policy leer     on conta.apuntes  for select to authenticated using (conta.puede_leer(empresa_id));
create policy escribir on conta.apuntes  for all to authenticated
  using (conta.puede_escribir(empresa_id)) with check (conta.puede_escribir(empresa_id));

-- ---------------------------------------------------------------------
-- Permisos de la API (Supabase usa los roles anon y authenticated)
-- anon (sin sesión) no ve NADA del ERP.
-- ---------------------------------------------------------------------
revoke all on schema conta from anon, public;
revoke all on all tables in schema conta from anon, public;
revoke execute on all functions in schema conta from anon, public;

grant usage on schema conta to authenticated;
grant select on all tables in schema conta to authenticated;
grant insert, update, delete on
  conta.empresas, conta.usuarios_empresa, conta.ejercicios, conta.periodos,
  conta.cuentas, conta.terceros, conta.asientos, conta.apuntes
  to authenticated;
grant execute on all functions in schema conta to authenticated;
