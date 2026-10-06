-- =====================================================================
-- 0015 · GUEST ACCESS · Ver las empresas demo sin registrarse (bloque K3)
-- ---------------------------------------------------------------------
-- La web usa los "Anonymous Sign-Ins" de Supabase: el visitante pulsa "Ver demo" (o abre el enlace
-- con ?demo) y recibe una sesión temporal SIN email. Para la base de datos es un usuario 'authenticated'
-- más, pero su token lleva la marca is_anonymous = true.
--
-- Regla: un INVITADO solo puede LEER las empresas demo.
--   · no crea empresas (límite 0 y error explícito)
--   · can_write / is_admin devuelven siempre false → no escribe en ninguna tabla ni función
--   · puede guardar su idioma (user_settings), como cualquier visitante
-- Equivale a la empresa demo CRONUS de Business Central o al sistema IDES de SAP: se ven, no se tocan.
--
-- Requisito en Supabase: Authentication → Sign In / Providers → "Allow anonymous sign-ins" = ON
-- Limpieza periódica (SQL Editor):  delete from auth.users where is_anonymous and created_at < now() - interval '30 days';
-- =====================================================================

create or replace function erp.is_anonymous()
returns boolean language sql stable as $$
  select coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false)
$$;

-- Permisos de escritura: nunca para un invitado
create or replace function erp.can_write(p_company uuid)
returns boolean language sql stable as $$
  select not erp.is_anonymous() and coalesce(erp.my_role(p_company) in ('admin', 'accountant'), false)
$$;

create or replace function erp.is_admin(p_company uuid)
returns boolean language sql stable as $$
  select not erp.is_anonymous() and coalesce(erp.my_role(p_company) = 'admin', false)
$$;

-- Perfil: el invitado es 'guest' con 0 empresas
create or replace function erp.my_profile()
returns table (app_role text, max_companies int, companies_created int)
language sql stable security definer set search_path = erp, public as $$
  select case when erp.is_anonymous() then 'guest' else coalesce(p.app_role, 'member') end,
         case when erp.is_anonymous() then 0 when p.user_id is null then 1 else p.max_companies end,
         (select count(*)::int from erp.companies c where c.created_by = auth.uid())
  from (select auth.uid() as uid) me
  left join erp.app_profiles p on p.user_id = me.uid;
$$;

-- Alta de empresas: el invitado no puede (mensaje claro), el resto como en 0007
create or replace function erp.tg_company_rules()
returns trigger language plpgsql security definer set search_path = erp, public as $$
declare
  v_max     int;
  v_created int;
begin
  if auth.uid() is null then
    return new;
  end if;

  if erp.is_anonymous() then
    raise exception 'Guest visitors can only view the demo companies: sign up to create your own';
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

revoke execute on function erp.is_anonymous() from anon, public;
grant execute on function erp.is_anonymous() to authenticated;
