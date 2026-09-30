-- =====================================================================
-- 0006 · SECURITY: permissions and Row Level Security (multi-user)
-- ---------------------------------------------------------------------
-- Idea: cada fila lleva company_id; un usuario solo ve/toca las empresas
-- en las que figura en company_users, según su rol:
--   viewer      → consultar
--   accountant  → + cuentas, terceros y asientos
--   admin       → + ejercicios, periodos, usuarios y la propia empresa
-- En SAP serían objetos de autorización por sociedad; en BC, permission sets.
-- =====================================================================

-- Rol del usuario actual en una empresa (null si no tiene acceso).
-- security definer: consulta company_users sin quedar atrapada en su propia RLS.
create or replace function erp.my_role(p_company uuid)
returns text language sql stable security definer set search_path = erp, public as $$
  select role from erp.company_users where company_id = p_company and user_id = auth.uid();
$$;

create or replace function erp.can_read(p_company uuid)
returns boolean language sql stable as $$ select erp.my_role(p_company) is not null $$;

create or replace function erp.can_write(p_company uuid)
returns boolean language sql stable as $$ select erp.my_role(p_company) in ('admin', 'accountant') $$;

create or replace function erp.is_admin(p_company uuid)
returns boolean language sql stable as $$ select erp.my_role(p_company) = 'admin' $$;

create or replace function erp.fiscal_year_company(p_fiscal_year uuid)
returns uuid language sql stable security definer set search_path = erp, public as $$
  select company_id from erp.fiscal_years where id = p_fiscal_year;
$$;

-- ---------------------------------------------------------------------
-- Activar RLS en todas las tablas · Enable RLS on every table
-- ---------------------------------------------------------------------
alter table erp.companies           enable row level security;
alter table erp.company_users       enable row level security;
alter table erp.user_settings       enable row level security;
alter table erp.fiscal_years        enable row level security;
alter table erp.accounting_periods  enable row level security;
alter table erp.coa_template        enable row level security;
alter table erp.gl_accounts         enable row level security;
alter table erp.business_partners   enable row level security;
alter table erp.tax_codes           enable row level security;
alter table erp.journal_entries     enable row level security;
alter table erp.journal_lines       enable row level security;

-- Catálogos globales: todos los usuarios con sesión los leen, nadie los modifica desde la web
create policy read on erp.coa_template for select to authenticated using (true);
create policy read on erp.tax_codes    for select to authenticated using (true);

-- Preferencias: cada usuario solo ve y cambia las suyas
create policy own on erp.user_settings for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Companies (created_by en el SELECT: permite leer la fila recién creada en el mismo INSERT … RETURNING)
create policy read   on erp.companies for select to authenticated
  using (erp.can_read(id) or created_by = auth.uid());
create policy insert on erp.companies for insert to authenticated with check (created_by = auth.uid());
create policy update on erp.companies for update to authenticated
  using (erp.is_admin(id)) with check (erp.is_admin(id));
create policy delete on erp.companies for delete to authenticated using (erp.is_admin(id));

-- Company users: los miembros ven al equipo; solo el admin lo gestiona
create policy read   on erp.company_users for select to authenticated using (erp.can_read(company_id));
create policy manage on erp.company_users for all to authenticated
  using (erp.is_admin(company_id)) with check (erp.is_admin(company_id));

-- Fiscal years and periods: leer miembros, gestionar admin
create policy read   on erp.fiscal_years for select to authenticated using (erp.can_read(company_id));
create policy manage on erp.fiscal_years for all to authenticated
  using (erp.is_admin(company_id)) with check (erp.is_admin(company_id));

create policy read   on erp.accounting_periods for select to authenticated
  using (erp.can_read(erp.fiscal_year_company(fiscal_year_id)));
create policy manage on erp.accounting_periods for all to authenticated
  using (erp.is_admin(erp.fiscal_year_company(fiscal_year_id)))
  with check (erp.is_admin(erp.fiscal_year_company(fiscal_year_id)));

-- Accounts, partners, entries and lines: leer miembros, escribir admin y accountant
create policy read  on erp.gl_accounts       for select to authenticated using (erp.can_read(company_id));
create policy write on erp.gl_accounts       for all to authenticated
  using (erp.can_write(company_id)) with check (erp.can_write(company_id));

create policy read  on erp.business_partners for select to authenticated using (erp.can_read(company_id));
create policy write on erp.business_partners for all to authenticated
  using (erp.can_write(company_id)) with check (erp.can_write(company_id));

create policy read  on erp.journal_entries   for select to authenticated using (erp.can_read(company_id));
create policy write on erp.journal_entries   for all to authenticated
  using (erp.can_write(company_id)) with check (erp.can_write(company_id));

create policy read  on erp.journal_lines     for select to authenticated using (erp.can_read(company_id));
create policy write on erp.journal_lines     for all to authenticated
  using (erp.can_write(company_id)) with check (erp.can_write(company_id));

-- ---------------------------------------------------------------------
-- Permisos de la API (Supabase usa los roles anon y authenticated)
-- anon (sin sesión) no ve NADA del ERP.
-- ---------------------------------------------------------------------
revoke all on schema erp from anon, public;
revoke all on all tables in schema erp from anon, public;
revoke execute on all functions in schema erp from anon, public;

grant usage on schema erp to authenticated;
grant select on all tables in schema erp to authenticated;
grant insert, update, delete on
  erp.companies, erp.company_users, erp.user_settings, erp.fiscal_years, erp.accounting_periods,
  erp.gl_accounts, erp.business_partners, erp.journal_entries, erp.journal_lines
  to authenticated;
grant execute on all functions in schema erp to authenticated;
