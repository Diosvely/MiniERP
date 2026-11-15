-- =====================================================================
-- erp.tg_company_rules · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0007_demo_and_limits 0015_guest_access 0027_members 0072_temporary_companies 0092_balance_and_permissions_fixes 0095_equity_and_company_rules   →   la vigente es la de 0095_equity_and_company_rules
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_company_rules()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
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
    -- v0.60.3 (SEG-10) · quién la creó cuenta para el límite de empresas: no se cambia
    if new.created_by is distinct from old.created_by then
      raise exception 'The creator of a company cannot be changed';
    end if;
    -- v0.60.3 (SEG-10) · la semilla de una sintética es su identidad (su huella): no se cambia una vez puesta
    if old.synthetic_seed is not null and (new.synthetic_seed is distinct from old.synthetic_seed
        or new.synthetic_profile is distinct from old.synthetic_profile
        or new.synthetic_months is distinct from old.synthetic_months) then
      raise exception 'The seed of a synthetic company cannot be changed';
    end if;
    -- v0.60.6 (SEG-21) · los ajustes que dan forma a la contabilidad, con las mismas reglas que sus funciones
    if new.tax_territory is distinct from old.tax_territory then
      raise exception 'The tax territory cannot be changed after the company is created';
    end if;
    if new.posting_account_digits is distinct from old.posting_account_digits then
      raise exception 'The digits of the posting accounts cannot be changed after the company is created';
    end if;
    if new.legal_form is distinct from old.legal_form
       and exists (select 1 from erp.equity_operations where company_id = new.id and status = 'posted') then
      raise exception 'The company already has equity operations: undo them before changing the legal form';
    end if;
    if (new.start_date is distinct from old.start_date or new.monthly is distinct from old.monthly)
       and exists (select 1 from erp.journal_entries j where j.company_id = new.id) then
      raise exception 'The company already has entries: the start date can only be set in a new company';
    end if;
    if (new.case_key is distinct from old.case_key or new.case_mode is distinct from old.case_mode)
       and old.case_key is not null then
      raise exception 'The practice case of a company cannot be changed';
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
    -- v0.60.3 (SEG-10) · una sintética nunca es demo (la misma regla que erp.set_company_demo, 0086)
    if new.is_demo and new.synthetic_seed is not null then
      raise exception 'A synthetic company cannot be published as demo';
    end if;
  end if;

  return new;
end $function$
;
