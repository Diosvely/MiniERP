-- =====================================================================
-- erp.tg_company_rules · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0007_demo_and_limits 0015_guest_access 0027_members 0072_temporary_companies   →   la vigente es la de 0072_temporary_companies
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_company_rules()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
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
end $function$
;
