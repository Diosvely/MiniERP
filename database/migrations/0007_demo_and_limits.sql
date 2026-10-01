-- =====================================================================
-- 0007 · DEMO COMPANIES & USER LIMITS · Empresas demo y límites por usuario
-- ---------------------------------------------------------------------
-- Objetivo: compartir la web en LinkedIn con seguridad.
--   owner   (propietario / super usuario) → empresas ilimitadas; puede publicar empresas como DEMO
--   member  (cualquier usuario registrado) → máximo 1 empresa propia (configurable por usuario)
--   Empresas DEMO (is_demo = true) → cualquier usuario con sesión las LEE; solo sus miembros las editan.
--
-- En BC/SAP esto sería: "license type" o perfil de usuario + permisos de solo lectura sobre una sociedad.
-- Ver docs/decisiones/0004-demo-y-limites.md
-- =====================================================================

-- ---------------------------------------------------------------------
-- APP PROFILES · Perfil de aplicación de cada usuario
-- Si un usuario no tiene fila aquí, es 'member' con límite 1.
-- ---------------------------------------------------------------------
create table erp.app_profiles (
  user_id        uuid primary key,
  app_role       text not null default 'member' check (app_role in ('owner', 'member')),
  max_companies  smallint check (max_companies >= 0),   -- null = sin límite
  created_at     timestamptz not null default now()
);
comment on table erp.app_profiles is
  'Application-level profile: owner (unlimited, can publish demos) or member (limited companies).';

create or replace function erp.is_owner()
returns boolean language sql stable security definer set search_path = erp, public as $$
  select exists (select 1 from erp.app_profiles where user_id = auth.uid() and app_role = 'owner');
$$;

-- Perfil del usuario actual para la web: rol, límite y empresas creadas
create or replace function erp.my_profile()
returns table (app_role text, max_companies int, companies_created int)
language sql stable security definer set search_path = erp, public as $$
  select coalesce(p.app_role, 'member'),
         case when p.user_id is null then 1 else p.max_companies end,
         (select count(*)::int from erp.companies c where c.created_by = auth.uid())
  from (select auth.uid() as uid) me
  left join erp.app_profiles p on p.user_id = me.uid;
$$;

-- ---------------------------------------------------------------------
-- DEMO FLAG · Marca de empresa demo
-- ---------------------------------------------------------------------
alter table erp.companies add column is_demo boolean not null default false;
comment on column erp.companies.is_demo is 'Published as read-only demo for every signed-in user (only owners can set it).';

-- ---------------------------------------------------------------------
-- Reglas al crear / modificar empresas
--   1. Límite de empresas por usuario (salvo owner)
--   2. Solo un owner puede publicar o despublicar una empresa como demo
-- Desde el SQL Editor (sin sesión, auth.uid() = null) no se aplican: eres el administrador.
-- ---------------------------------------------------------------------
create or replace function erp.tg_company_rules()
returns trigger language plpgsql security definer set search_path = erp, public as $$
declare
  v_max     int;
  v_created int;
begin
  if auth.uid() is null then
    return new;
  end if;

  if tg_op = 'INSERT' then
    select max_companies into v_max from erp.my_profile();
    select companies_created into v_created from erp.my_profile();
    if v_max is not null and v_created >= v_max then
      raise exception 'Company limit reached: your account can create % compan%', v_max,
        case when v_max = 1 then 'y' else 'ies' end;
    end if;
  end if;

  if (tg_op = 'INSERT' and new.is_demo)
     or (tg_op = 'UPDATE' and new.is_demo is distinct from old.is_demo) then
    if not erp.is_owner() then
      raise exception 'Only the application owner can publish a company as demo';
    end if;
  end if;

  return new;
end $$;

create trigger company_rules
  before insert or update on erp.companies
  for each row execute function erp.tg_company_rules();

-- ---------------------------------------------------------------------
-- LECTURA: miembros de la empresa + cualquier usuario si la empresa es demo.
-- Se redefine can_read(); todas las políticas "read" de 0006 la usan, así que
-- cuentas, asientos, apuntes, informes… de una empresa demo pasan a ser legibles.
-- La ESCRITURA no cambia: sigue exigiendo rol admin/accountant en la empresa.
-- ---------------------------------------------------------------------
create or replace function erp.can_read(p_company uuid)
returns boolean language sql stable security definer set search_path = erp, public as $$
  select erp.my_role(p_company) is not null
      or exists (select 1 from erp.companies where id = p_company and is_demo);
$$;

-- El equipo de una empresa (quién es miembro) solo lo ven sus miembros, no los visitantes de la demo
drop policy read on erp.company_users;
create policy read on erp.company_users for select to authenticated
  using (erp.my_role(company_id) is not null);

-- ---------------------------------------------------------------------
-- VISTA para la web: mis empresas + demos, con mi rol en cada una
-- (my_role null → solo lectura porque es demo de otro usuario)
-- ---------------------------------------------------------------------
create or replace view erp.v_my_companies with (security_invoker = true) as
select c.id, c.name, c.vat_registration_no, c.industry, c.tax_territory,
       c.posting_account_digits, c.is_demo, c.created_at,
       erp.my_role(c.id) as my_role
from erp.companies c;

-- ---------------------------------------------------------------------
-- Seguridad de las tablas nuevas
-- ---------------------------------------------------------------------
alter table erp.app_profiles enable row level security;
create policy own on erp.app_profiles for select to authenticated using (user_id = auth.uid());
-- Nadie modifica perfiles desde la web: se asignan desde el SQL Editor.

revoke all on erp.app_profiles, erp.v_my_companies from anon, public;
grant select on erp.app_profiles, erp.v_my_companies to authenticated;
revoke execute on function erp.is_owner(), erp.my_profile(), erp.tg_company_rules() from anon, public;
grant execute on function erp.is_owner(), erp.my_profile() to authenticated;
