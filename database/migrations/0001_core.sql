-- =====================================================================
-- 0001 · CORE: companies, company users, fiscal years, accounting periods
-- ---------------------------------------------------------------------
-- Nombres en inglés al estilo de Business Central (BC) y SAP. Comentarios en español.
--
-- Equivalencias / Equivalents:
--   companies            ≈ BC "Company"             ≈ SAP "Company Code" (T001 / BUKRS)   · Empresa / sociedad
--   company_users        ≈ BC "User Permissions"    ≈ SAP authorizations per company code · Usuarios por empresa
--   fiscal_years         ≈ BC "Accounting Periods"  ≈ SAP "Fiscal Year Variant"            · Ejercicio contable
--   accounting_periods   ≈ BC period (month)        ≈ SAP "Posting Periods" (OB52)         · Periodo contable (mes)
-- Todo vive en el schema "erp" para no mezclarse con otras apps del mismo proyecto de Supabase.
-- =====================================================================

create schema if not exists erp;
comment on schema erp is 'Mini ERP · Spanish general ledger (PGC, VAT, IGIC)';

create extension if not exists pgcrypto;  -- gen_random_uuid()

-- ---------------------------------------------------------------------
-- COMPANIES · Empresas
-- ---------------------------------------------------------------------
create table erp.companies (
  id                      uuid primary key default gen_random_uuid(),
  name                    text not null,
  vat_registration_no     text,                                   -- NIF / CIF (BC: "VAT Registration No.")
  industry                text not null                           -- sector
                          check (industry in ('retail', 'manufacturing', 'ecommerce', 'services')),
  -- Territorio fiscal: decide si la empresa repercute IVA (mainland) o IGIC (canary_islands)
  tax_territory           text not null
                          check (tax_territory in ('mainland', 'canary_islands')),
  chart_of_accounts       text not null default 'PGC'            -- plan contable
                          check (chart_of_accounts in ('PGC', 'PGC_PYMES')),
  -- Longitud fija de las subcuentas (cuentas de movimiento). Ej: 8 → 43000001
  posting_account_digits  smallint not null default 8 check (posting_account_digits between 5 and 12),
  currency_code           char(3) not null default 'EUR',
  created_by              uuid default auth.uid(),
  created_at              timestamptz not null default now()
);
comment on table erp.companies is 'Companies (sociedades). Each one has its own chart of accounts and fiscal years.';

-- ---------------------------------------------------------------------
-- COMPANY USERS · Usuarios por empresa (multiusuario)
-- user_id = id de Supabase Auth (auth.users.id)
-- ---------------------------------------------------------------------
create table erp.company_users (
  company_id  uuid not null references erp.companies(id) on delete cascade,
  user_id     uuid not null,
  role        text not null default 'viewer'
              check (role in ('admin', 'accountant', 'viewer')),   -- administrador, contable, solo lectura
  created_at  timestamptz not null default now(),
  primary key (company_id, user_id)
);
comment on table erp.company_users is
  'Who can access each company. admin: everything · accountant: entries and master data · viewer: read only.';

-- Quien crea la empresa pasa a ser su admin automáticamente.
-- Desde el SQL Editor (sin sesión) hay que indicar created_by.
create or replace function erp.tg_company_add_admin()
returns trigger language plpgsql security definer set search_path = erp, public as $$
begin
  if new.created_by is null then
    raise exception 'Set created_by (an auth.users id) when creating a company without a session';
  end if;
  insert into erp.company_users (company_id, user_id, role)
  values (new.id, new.created_by, 'admin');
  return new;
end $$;

create trigger company_add_admin
  after insert on erp.companies
  for each row execute function erp.tg_company_add_admin();

-- ---------------------------------------------------------------------
-- FISCAL YEARS & ACCOUNTING PERIODS · Ejercicios y periodos
-- ---------------------------------------------------------------------
create table erp.fiscal_years (
  id             uuid primary key default gen_random_uuid(),
  company_id     uuid not null references erp.companies(id) on delete cascade,
  year           smallint not null,
  starting_date  date not null,
  ending_date    date not null,
  status         text not null default 'open' check (status in ('open', 'closed')),
  unique (company_id, year),
  check (ending_date > starting_date)
);

create table erp.accounting_periods (
  fiscal_year_id  uuid not null references erp.fiscal_years(id) on delete cascade,
  period_no       smallint not null check (period_no between 1 and 12),
  starting_date   date not null,
  ending_date     date not null,
  status          text not null default 'open' check (status in ('open', 'closed')),
  primary key (fiscal_year_id, period_no)
);
comment on table erp.accounting_periods is
  'Months of the fiscal year. A closed period does not accept postings (like OB52 in SAP).';

-- Crea un ejercicio natural (1 ene – 31 dic) con sus 12 periodos.
create or replace function erp.create_fiscal_year(p_company uuid, p_year int)
returns uuid language plpgsql as $$
declare
  v_id uuid;
  m    int;
begin
  insert into erp.fiscal_years (company_id, year, starting_date, ending_date)
  values (p_company, p_year, make_date(p_year, 1, 1), make_date(p_year, 12, 31))
  returning id into v_id;

  for m in 1..12 loop
    insert into erp.accounting_periods (fiscal_year_id, period_no, starting_date, ending_date)
    values (v_id, m,
            make_date(p_year, m, 1),
            (make_date(p_year, m, 1) + interval '1 month - 1 day')::date);
  end loop;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- USER SETTINGS · Preferencias de cada usuario (idioma de la interfaz)
-- Se guarda en la base de datos para que el idioma te siga en el móvil y en el ordenador.
-- ---------------------------------------------------------------------
create table erp.user_settings (
  user_id     uuid primary key default auth.uid(),
  language    text not null default 'es' check (language in ('es', 'en')),
  updated_at  timestamptz not null default now()
);
comment on table erp.user_settings is 'Per-user preferences, e.g. UI language (es / en).';
