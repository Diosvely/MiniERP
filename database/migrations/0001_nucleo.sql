-- =====================================================================
-- 0001 · NÚCLEO: empresas, usuarios por empresa, ejercicios y periodos
-- ---------------------------------------------------------------------
-- Equivalencias:
--   empresas          ≈ BC "Company"              ≈ SAP "Sociedad" (BUKRS, tabla T001)
--   usuarios_empresa  ≈ BC "User Permissions"      ≈ SAP autorizaciones por sociedad
--   ejercicios        ≈ BC "Accounting Periods"    ≈ SAP "Variante de ejercicio"
--   periodos          ≈ BC periodo contable        ≈ SAP periodos (OB52: abrir/cerrar)
-- Todo vive en el schema "conta" para no mezclarse con otras apps del proyecto.
-- =====================================================================

create schema if not exists conta;
comment on schema conta is 'Mini ERP · contabilidad general española (PGC, IVA, IGIC)';

create extension if not exists pgcrypto;  -- gen_random_uuid()

-- ---------------------------------------------------------------------
-- EMPRESAS
-- ---------------------------------------------------------------------
create table conta.empresas (
  id                 uuid primary key default gen_random_uuid(),
  nombre             text not null,
  nif                text,
  sector             text not null
                     check (sector in ('retail', 'industria', 'ecommerce', 'servicios')),
  -- Territorio fiscal de la empresa: decide si repercute IVA o IGIC.
  territorio         text not null
                     check (territorio in ('peninsula', 'canarias')),
  plan_contable      text not null default 'PGC'
                     check (plan_contable in ('PGC', 'PGC_PYMES')),
  -- Longitud fija de las subcuentas (las cuentas donde se apunta). Ej: 8 → 43000001
  digitos_subcuenta  smallint not null default 8 check (digitos_subcuenta between 5 and 12),
  moneda             char(3) not null default 'EUR',
  creado_por         uuid default auth.uid(),
  created_at         timestamptz not null default now()
);
comment on table conta.empresas is 'Sociedades. Cada una tiene su propio plan de cuentas y ejercicios.';

-- ---------------------------------------------------------------------
-- USUARIOS POR EMPRESA (multiusuario)
-- user_id es el id de Supabase Auth (auth.users.id)
-- ---------------------------------------------------------------------
create table conta.usuarios_empresa (
  empresa_id  uuid not null references conta.empresas(id) on delete cascade,
  user_id     uuid not null,
  rol         text not null default 'lectura'
              check (rol in ('admin', 'contable', 'lectura')),
  created_at  timestamptz not null default now(),
  primary key (empresa_id, user_id)
);
comment on table conta.usuarios_empresa is
  'Quién accede a cada empresa. admin: todo · contable: asientos y maestros · lectura: solo consultar.';

-- Quien crea la empresa pasa a ser su admin automáticamente.
-- Si se crea desde el SQL Editor (sin sesión), hay que indicar creado_por.
create or replace function conta.tg_empresa_alta_admin()
returns trigger language plpgsql security definer set search_path = conta, public as $$
begin
  if new.creado_por is null then
    raise exception 'Indica creado_por (id de auth.users) al crear una empresa sin sesión iniciada';
  end if;
  insert into conta.usuarios_empresa (empresa_id, user_id, rol)
  values (new.id, new.creado_por, 'admin');
  return new;
end $$;

create trigger empresa_alta_admin
  after insert on conta.empresas
  for each row execute function conta.tg_empresa_alta_admin();

-- ---------------------------------------------------------------------
-- EJERCICIOS Y PERIODOS
-- ---------------------------------------------------------------------
create table conta.ejercicios (
  id            uuid primary key default gen_random_uuid(),
  empresa_id    uuid not null references conta.empresas(id) on delete cascade,
  anio          smallint not null,
  fecha_inicio  date not null,
  fecha_fin     date not null,
  estado        text not null default 'abierto' check (estado in ('abierto', 'cerrado')),
  unique (empresa_id, anio),
  check (fecha_fin > fecha_inicio)
);

create table conta.periodos (
  ejercicio_id  uuid not null references conta.ejercicios(id) on delete cascade,
  numero        smallint not null check (numero between 1 and 12),
  fecha_inicio  date not null,
  fecha_fin     date not null,
  estado        text not null default 'abierto' check (estado in ('abierto', 'cerrado')),
  primary key (ejercicio_id, numero)
);
comment on table conta.periodos is 'Meses del ejercicio. Un periodo cerrado no admite asientos (como OB52 en SAP).';

-- Crea un ejercicio natural (1 ene – 31 dic) con sus 12 periodos.
create or replace function conta.crear_ejercicio(p_empresa uuid, p_anio int)
returns uuid language plpgsql as $$
declare
  v_id uuid;
  m    int;
begin
  insert into conta.ejercicios (empresa_id, anio, fecha_inicio, fecha_fin)
  values (p_empresa, p_anio, make_date(p_anio, 1, 1), make_date(p_anio, 12, 31))
  returning id into v_id;

  for m in 1..12 loop
    insert into conta.periodos (ejercicio_id, numero, fecha_inicio, fecha_fin)
    values (v_id, m,
            make_date(p_anio, m, 1),
            (make_date(p_anio, m, 1) + interval '1 month - 1 day')::date);
  end loop;
  return v_id;
end $$;
