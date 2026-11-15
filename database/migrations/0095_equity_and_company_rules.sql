-- =====================================================================
-- 0095 · v0.60.6 · Operaciones societarias y ajustes de la empresa por la puerta de atrás
-- ---------------------------------------------------------------------
-- Aprobado por Diosvely el 15-11-2026.
--   AF-11 · si las pérdidas dejan el patrimonio neto por debajo del capital, el beneficio compensa primero y la reserva
--           legal se dota solo con lo que quede (art. 273.2 LSC; art. 28.3 Resolución ICAC 5-3-2019).
--   AF-14 · si no lo dejan por debajo, primero la reserva legal («en todo caso», art. 274.1 LSC) y el resto puede
--           compensar pérdidas (compensar es voluntario en este caso).
--   AF-15 · (opción b) el dividendo solo exige que el patrimonio neto no quede por debajo del capital (art. 273.2 LSC);
--           ya no se bloquea por quedar pérdidas sin compensar.
--   AF-12 · una SL no reduce capital por pérdidas mientras tenga cualquier reserva (110, 112, 113, 114, 115, 119;
--           art. 322.1 LSC); la reserva legal compensa pérdidas si no hay otras reservas disponibles (art. 274.2 LSC).
--   AF-13 · después de una reducción de capital por pérdidas, siempre, no hay dividendo (ni a cuenta) si la reserva
--           legal no llega al 10 % del capital (art. 326 LSC).
--   SEG-21 · los ajustes de la empresa (territorio, dígitos, forma jurídica, inicio, mes a mes, caso) solo cambian
--            con sus reglas, también con una escritura directa por la API.
--   SEG-22 · los meses solo cambian con el cierre y la reapertura; el ejercicio va de enero a diciembre y no cambia
--            sus fechas; un asiento solo se contabiliza en una fecha que tenga su mes (corrige el hueco de SEG-14).
--   H-079 · la consulta de IA se devuelve si el modelo falla (erp.ai_consume da un justificante; erp.ai_refund lo usa
--           una vez).
--   H-49  · erp.run_audit_checks, igual, sin la cifra de un diario de estudio en un comentario.
-- Pruebas: fase 55 (operaciones societarias), fase 80 (SEG-21, SEG-22) y fase 21 (H-079).
-- =====================================================================

-- ---------- AF-11, AF-14, AF-15 y AF-13 · Reparto del resultado ----------
create or replace function erp.equity_distribution_preview(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = erp, public set jit = off as $$
declare
  v_company uuid := (p->>'company_id')::uuid; v_date date := (p->>'date')::date;
  v_form text; v_res numeric; v_cap numeric; v_res112 numeric; v_losses numeric; v_interim numeric; v_nw numeric;
  v_offset numeric; v_legal_full numeric; v_legal_min numeric; v_legal numeric; v_div numeric; v_avail numeric; v_vol numeric;
  v_warn jsonb := '[]'; v_ok boolean := true; v_below boolean; v_min10 numeric;
begin
  if not erp.can_read(v_company) then raise exception 'No permission to read this company'; end if;
  select legal_form into v_form from erp.companies where id = v_company;
  v_res := erp.equity_bal(v_company, '129', v_date);
  v_cap := erp.equity_bal(v_company, '100', v_date);
  v_res112 := erp.equity_bal(v_company, '112', v_date);
  v_losses := -erp.equity_bal(v_company, '121', v_date);
  v_interim := -erp.equity_bal(v_company, '557', v_date);
  v_nw := erp.equity_net_worth(v_company, v_date, false) + v_interim;   -- antes del reparto (el dividendo a cuenta es parte del dividendo)
  v_div := round(coalesce((p->>'dividend')::numeric, v_interim), 2);
  if v_res = 0 then
    return jsonb_build_object('result', 0, 'ok', false, 'warnings', jsonb_build_array(jsonb_build_object('code', 'no_result')));
  end if;
  if v_res < 0 then
    -- pérdida: a la 121 y nada más
    if v_div > 0 or v_interim > 0 then v_ok := false; v_warn := v_warn || jsonb_build_object('code', 'dividend_with_loss'); end if;
    return jsonb_build_object('result', v_res, 'loss', -v_res, 'legal_reserve', 0, 'legal_reserve_min', 0, 'offset_losses', 0,
      'dividend', 0, 'interim', v_interim, 'complementary', 0, 'voluntary', 0, 'net_worth_before', v_nw, 'net_worth_after', v_nw,
      'capital', v_cap, 'ok', v_ok, 'warnings', v_warn, 'legal_form', v_form);
  end if;
  -- beneficio: si las pérdidas dejan el patrimonio neto por debajo del capital, primero compensar (art. 273.2 LSC y
  -- art. 28.3 Resolución ICAC 5-3-2019); si no, primero la reserva legal (art. 274.1 LSC), y el resto puede compensar
  -- pérdidas (v0.60.6, AF-11 y AF-14)
  v_legal_full := erp.equity_legal_reserve(v_form, v_cap, v_res112, v_res);
  v_below := v_losses > 0 and v_nw < v_cap;
  if v_below then
    v_offset := least(v_losses, v_res, coalesce((p->>'offset_losses')::numeric, v_losses));
    if v_offset < least(v_losses, v_res) then
      v_ok := false; v_warn := v_warn || jsonb_build_object('code', 'losses_must_be_offset', 'min', least(v_losses, v_res));
    end if;
    v_legal_min := least(v_legal_full, greatest(0, v_res - v_offset));
    if v_legal_min < v_legal_full then
      v_warn := v_warn || jsonb_build_object('code', 'losses_before_legal_reserve', 'min', v_legal_min);
    end if;
  else
    v_legal_min := v_legal_full;
    v_offset := least(v_losses, greatest(0, v_res - v_legal_min), coalesce((p->>'offset_losses')::numeric, v_losses));
  end if;
  v_legal := round(coalesce((p->>'legal_reserve')::numeric, v_legal_min), 2);
  if v_legal < v_legal_min then v_ok := false; v_warn := v_warn || jsonb_build_object('code', 'legal_reserve_below_min', 'min', v_legal_min); end if;
  v_avail := v_res - v_offset - v_legal;
  v_vol := v_avail - v_div;
  if v_div < v_interim then v_ok := false; v_warn := v_warn || jsonb_build_object('code', 'dividend_below_interim', 'interim', v_interim); end if;
  if v_vol < 0 then v_ok := false; v_warn := v_warn || jsonb_build_object('code', 'dividend_above_available', 'available', v_avail); end if;
  -- art. 273.2: después del reparto, el patrimonio neto no puede quedar por debajo del capital (AF-15, opción b: quedar
  -- pérdidas sin compensar ya no lo impide por sí solo)
  if v_div > 0 and v_nw - v_div < v_cap then
    v_ok := false; v_warn := v_warn || jsonb_build_object('code', 'net_worth_below_capital', 'net_worth_after', v_nw - v_div, 'capital', v_cap);
  end if;
  -- art. 326 (AF-13): después de una reducción de capital por pérdidas, siempre, la reserva legal al 10 % del capital
  if v_div > 0 and exists (select 1 from erp.equity_operations o where o.company_id = v_company and o.kind = 'capital_reduction'
                           and o.status = 'posted' and o.op_date <= v_date) then
    v_min10 := round(v_cap * 0.10, 2);
    if v_res112 + v_legal < v_min10 then
      v_ok := false; v_warn := v_warn || jsonb_build_object('code', 'legal_reserve_below_10_after_reduction', 'min', v_min10 - v_res112);
    end if;
  end if;
  if v_losses > 0 and v_offset < v_losses then v_warn := v_warn || jsonb_build_object('code', 'losses_left', 'left', v_losses - v_offset); end if;
  return jsonb_build_object('result', v_res, 'loss', 0, 'offset_losses', v_offset, 'legal_reserve', v_legal, 'legal_reserve_min', v_legal_min,
    'dividend', v_div, 'interim', v_interim, 'complementary', v_div - v_interim, 'voluntary', v_vol, 'available', v_avail,
    'net_worth_before', v_nw, 'net_worth_after', v_nw - v_div, 'capital', v_cap, 'legal_reserve_before', v_res112,
    'low_capital_sl', v_form = 'sl' and v_cap < 3000, 'ok', v_ok, 'warnings', v_warn, 'legal_form', v_form);
end $$;

-- ---------- AF-13 · Dividendo a cuenta después de una reducción de capital ----------
create or replace function erp.equity_interim_preview(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = erp, public set jit = off as $$
declare
  v_company uuid := (p->>'company_id')::uuid; v_date date := (p->>'date')::date; v_form text;
  v_result numeric; v_losses numeric; v_tax numeric; v_legal numeric; v_max numeric; v_amt numeric; v_cash numeric; v_paid numeric; v_warn jsonb := '[]';
  v_cap numeric; v_res112 numeric;
begin
  if not erp.can_read(v_company) then raise exception 'No permission to read this company'; end if;
  select legal_form into v_form from erp.companies where id = v_company;
  v_result := erp.equity_bal(v_company, '6', v_date) + erp.equity_bal(v_company, '7', v_date);   -- antes de impuestos (sin 630)
  v_result := v_result - erp.equity_bal(v_company, '630', v_date);
  v_losses := -erp.equity_bal(v_company, '121', v_date);
  v_tax := round(coalesce((p->>'estimated_tax')::numeric, greatest(v_result, 0) * 0.25), 2);
  v_cap := erp.equity_bal(v_company, '100', v_date);
  v_res112 := erp.equity_bal(v_company, '112', v_date);
  v_legal := erp.equity_legal_reserve(v_form, v_cap, v_res112, v_result - v_tax);
  v_paid := -erp.equity_bal(v_company, '557', v_date);   -- dividendos a cuenta ya acordados este ejercicio
  v_max := greatest(0, v_result - v_losses - v_tax - v_legal - v_paid);
  v_amt := round(coalesce((p->>'amount')::numeric, 0), 2);
  v_cash := -erp.equity_bal(v_company, '57', v_date);
  if v_amt > v_max then v_warn := v_warn || jsonb_build_object('code', 'interim_above_limit', 'max', v_max); end if;
  if v_amt > v_cash then v_warn := v_warn || jsonb_build_object('code', 'interim_no_liquidity', 'cash', v_cash); end if;
  -- v0.60.6 (AF-13, art. 326 LSC): después de una reducción de capital por pérdidas, la reserva legal al 10 % del capital
  if v_amt > 0 and v_res112 < round(v_cap * 0.10, 2)
     and exists (select 1 from erp.equity_operations o where o.company_id = v_company and o.kind = 'capital_reduction'
                 and o.status = 'posted' and o.op_date <= v_date) then
    v_warn := v_warn || jsonb_build_object('code', 'legal_reserve_below_10_after_reduction', 'min', round(v_cap * 0.10, 2) - v_res112);
  end if;
  return jsonb_build_object('result_since_close', v_result, 'prior_losses', v_losses, 'estimated_tax', v_tax, 'legal_reserve', v_legal,
    'already_paid', v_paid, 'max', v_max, 'amount', v_amt, 'cash', v_cash, 'ok', v_amt > 0 and jsonb_array_length(v_warn) = 0, 'warnings', v_warn);
end $$;

-- ---------- AF-12 · Reducción de capital por pérdidas: la SL, con ninguna reserva ----------
create or replace function erp.equity_capital_reduction(p jsonb)
returns jsonb language plpgsql security definer set search_path = erp, public set jit = off as $$
declare
  v_company uuid := (p->>'company_id')::uuid; v_date date := (p->>'date')::date; v_code text; v_amt numeric; v_losses numeric;
  v_cap numeric; v_form text; e1 uuid; v_reserves numeric;
begin
  v_code := erp.equity_start(v_company, v_date);
  select legal_form into v_form from erp.companies where id = v_company;
  v_amt := round(coalesce((p->>'amount')::numeric, 0), 2);
  v_losses := -erp.equity_bal(v_company, '121', v_date); v_cap := erp.equity_bal(v_company, '100', v_date);
  if v_amt <= 0 or v_amt > v_losses then raise exception 'The reduction must be between 0 and the pending losses (%)', v_losses; end if;
  if v_form = 'sl' then
    -- v0.60.6 (AF-12): art. 322.1 LSC, la SL no reduce capital por pérdidas con cualquier clase de reservas
    select coalesce(sum(greatest(erp.equity_bal(v_company, r, v_date), 0)), 0) into v_reserves
    from unnest(array['110', '112', '113', '114', '115', '119']) r;
    if v_reserves > 0 then
      raise exception 'An SL cannot reduce capital for losses while it has any reserves (% in reserves; art. 322.1 LSC): offset the losses with them first', v_reserves;
    end if;
  else
    if erp.equity_bal(v_company, '113', v_date) > 0 then raise exception 'Use the voluntary reserves first: capital cannot be reduced for losses while there are reserves (art. 322 LSC)'; end if;
    if erp.equity_bal(v_company, '112', v_date) > round((v_cap - v_amt) * 0.10, 2) then
      raise exception 'The legal reserve would exceed 10 %% of the new capital: use it first (art. 322 LSC)';
    end if;
  end if;
  if v_cap - v_amt < (case v_form when 'sa' then 60000 else 1 end) then
    raise exception 'The capital would be below the legal minimum (art. 4 LSC)';
  end if;
  e1 := erp.equity_entry(v_company, v_date, 'Reducción de capital para compensar pérdidas', v_code,
          jsonb_build_array(erp.equity_line(erp.adjust_account(v_company, '100', 'Capital social'), v_amt, 0),
            erp.equity_line((select id from erp.gl_accounts where company_id = v_company and account_type = 'posting' and account_no like '121%' order by account_no limit 1), 0, v_amt)));
  return erp.equity_save(v_company, v_code, 'capital_reduction', v_date, 'Reducción de capital por pérdidas', p,
    jsonb_build_object('amount', v_amt, 'capital_after', v_cap - v_amt, 'losses_after', v_losses - v_amt), array[e1]);
end $$;

-- ---------- AF-12 · Compensar pérdidas con reservas: también la prima, la 115, la 119 y la reserva legal ----------
create or replace function erp.equity_loss_offset(p jsonb)
returns jsonb language plpgsql security definer set search_path = erp, public set jit = off as $$
declare
  v_company uuid := (p->>'company_id')::uuid; v_date date := (p->>'date')::date; v_code text; v_amt numeric; v_losses numeric;
  v_bal numeric; v_others numeric; e1 uuid; v_res text := coalesce(nullif(p->>'reserve', ''), '113'); v_name text;
begin
  v_code := erp.equity_start(v_company, v_date);
  if v_res not in ('113', '110', '115', '119', '112') then raise exception 'Reserve % cannot offset losses', v_res; end if;
  v_amt := round(coalesce((p->>'amount')::numeric, 0), 2);
  v_losses := -erp.equity_bal(v_company, '121', v_date); v_bal := erp.equity_bal(v_company, v_res, v_date);
  if v_amt <= 0 or v_amt > v_losses then raise exception 'The amount must be between 0 and the pending losses (%)', v_losses; end if;
  if v_amt > v_bal then raise exception 'Not enough balance in reserve % (balance %)', v_res, v_bal; end if;
  if v_res = '112' then
    -- art. 274.2 LSC: la reserva legal (hasta el 20 %) solo compensa pérdidas si no hay otras reservas disponibles
    select coalesce(sum(greatest(erp.equity_bal(v_company, r, v_date), 0)), 0) into v_others
    from unnest(array['110', '113', '115', '119']) r;
    if v_others > 0 then
      raise exception 'Use the other available reserves first (% available; art. 274.2 LSC)', v_others;
    end if;
  end if;
  v_name := case v_res when '113' then 'reservas voluntarias' when '110' then 'la prima de emisión' when '115' then 'reservas por pérdidas y ganancias actuariales'
                       when '119' then 'diferencias por ajuste del capital a euros' else 'la reserva legal' end;
  e1 := erp.equity_entry(v_company, v_date, 'Compensación de pérdidas con ' || v_name, v_code,
          jsonb_build_array(erp.equity_line((select g.id from erp.gl_accounts g where g.company_id = v_company and g.account_type = 'posting' and g.account_no like v_res || '%'
                                             order by (select coalesce(sum(l.credit - l.debit), 0) from erp.journal_lines l where l.gl_account_id = g.id) desc limit 1), v_amt, 0),
            erp.equity_line((select id from erp.gl_accounts where company_id = v_company and account_type = 'posting' and account_no like '121%' order by account_no limit 1), 0, v_amt)));
  return erp.equity_save(v_company, v_code, 'loss_offset', v_date, 'Compensación de pérdidas', p,
    jsonb_build_object('amount', v_amt, 'reserve', v_res, 'losses_after', v_losses - v_amt), array[e1]);
end $$;

-- ---------- SEG-21 · Los ajustes de la empresa solo cambian con sus reglas ----------
-- Copia de la versión de la 0092 con el bloque nuevo «v0.60.6 (SEG-21)». Las funciones de la web (set_legal_form,
-- start_accounting, load_case…) ya cumplen estas reglas: un PATCH directo, ahora también.
create or replace function erp.tg_company_rules()
returns trigger language plpgsql security definer set search_path = erp, public set jit = off as $$
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
end $$;

-- ---------- SEG-22 · Los meses, solo con el cierre y la reapertura ----------
-- close_month, reopen_month y start_accounting son security definer: no necesitan el permiso del usuario. El borrado
-- de una empresa o de un ejercicio va por cascada. El alta de los meses la hace erp.create_fiscal_year con la sesión del
-- usuario: se mantiene, con sus fechas comprobadas.
revoke update, delete on erp.accounting_periods from authenticated, anon;

create or replace function erp.tg_period_insert()
returns trigger language plpgsql set jit = off as $$
declare v_year int;
begin
  if current_user not in ('authenticated', 'anon') then return new; end if;   -- funciones de la base y administrador
  select year into v_year from erp.fiscal_years where id = new.fiscal_year_id;
  if new.starting_date is distinct from make_date(v_year, new.period_no, 1)
     or new.ending_date is distinct from (make_date(v_year, new.period_no, 1) + interval '1 month - 1 day')::date
     or new.status <> 'open' then
    raise exception 'A month of the fiscal year is created open and with its own dates: use erp.create_fiscal_year';
  end if;
  return new;
end $$;
drop trigger if exists period_insert on erp.accounting_periods;
create trigger period_insert before insert on erp.accounting_periods
  for each row execute function erp.tg_period_insert();
revoke execute on function erp.tg_period_insert() from anon, public, authenticated;

-- El ejercicio: de enero a diciembre, nace abierto y no cambia de año, fechas ni empresa (el estado lo protege
-- erp.tg_fiscal_year_status desde la 0017)
create or replace function erp.tg_fiscal_year_rules()
returns trigger language plpgsql set jit = off as $$
begin
  if current_user not in ('authenticated', 'anon') then return new; end if;   -- funciones de la base y administrador
  if tg_op = 'INSERT' then
    if new.status <> 'open' or new.starting_date is distinct from make_date(new.year, 1, 1)
       or new.ending_date is distinct from make_date(new.year, 12, 31) then
      raise exception 'A fiscal year is created open, from 1 January to 31 December: use erp.create_fiscal_year';
    end if;
  elsif new.company_id is distinct from old.company_id or new.year is distinct from old.year
        or new.starting_date is distinct from old.starting_date or new.ending_date is distinct from old.ending_date then
    raise exception 'The year and the dates of a fiscal year cannot be changed';
  end if;
  return new;
end $$;
drop trigger if exists fiscal_year_rules on erp.fiscal_years;
create trigger fiscal_year_rules before insert or update on erp.fiscal_years
  for each row execute function erp.tg_fiscal_year_rules();
revoke execute on function erp.tg_fiscal_year_rules() from anon, public, authenticated;

-- SEG-14 + SEG-22 · un asiento solo se contabiliza en una fecha que tenga su mes (copia de la 0094 con «not found»)
create or replace function erp.tg_entry_validate()
returns trigger language plpgsql set jit = off as $$
declare
  v_fy      erp.fiscal_years;
  v_period  erp.accounting_periods;
  v_debit   numeric(15,2);
  v_credit  numeric(15,2);
  v_lines   int;
  v_next    int;
begin
  if tg_op = 'UPDATE' and old.status = 'posted' then
    -- Único cambio permitido sobre un asiento contabilizado: marcarlo como anulado.
    if (to_jsonb(new) - 'reversed_by') <> (to_jsonb(old) - 'reversed_by')
       or old.reversed_by is not null then
      raise exception 'Entry % is posted and cannot be changed. Reverse it instead.', old.entry_no;
    end if;
    return new;
  end if;

  select * into v_fy from erp.fiscal_years where id = new.fiscal_year_id;
  if v_fy.company_id <> new.company_id then
    raise exception 'The fiscal year does not belong to the company of the entry';
  end if;
  if new.posting_date not between v_fy.starting_date and v_fy.ending_date then
    raise exception 'Posting date % is outside fiscal year %', new.posting_date, v_fy.year;
  end if;

  -- v0.60.5 (SEG-14) · De borrador a contabilizado: las mismas condiciones que erp.post_entry
  if new.status = 'posted'
     and (tg_op = 'INSERT' or old.status = 'draft')
     and coalesce(current_setting('erp.import_engine', true), '') <> 'on'
     and coalesce(current_setting('erp.deleting_company', true), '') <> 'on' then
    if tg_op = 'INSERT' then
      -- Un asiento nuevo no tiene líneas todavía: nace en borrador y se contabiliza después
      raise exception 'A new entry starts as a draft: post it with erp.post_entry';
    end if;
    select coalesce(sum(debit), 0), coalesce(sum(credit), 0), count(*)
    into v_debit, v_credit, v_lines
    from erp.journal_lines where entry_id = new.id;
    if v_lines < 2 then
      raise exception 'An entry needs at least 2 lines (it has %)', v_lines;
    end if;
    if v_debit <> v_credit then
      raise exception 'Unbalanced entry: debit % ≠ credit % (difference %)', v_debit, v_credit, v_debit - v_credit;
    end if;
    if v_fy.status <> 'open' then
      raise exception 'Fiscal year % is closed', v_fy.year;
    end if;
    select * into v_period from erp.accounting_periods
    where fiscal_year_id = new.fiscal_year_id and new.posting_date between starting_date and ending_date;
    -- v0.60.6 (SEG-22) · sin mes para esa fecha, tampoco
    if not found then
      raise exception 'There is no accounting period for %', new.posting_date;
    end if;
    if v_period.status <> 'open' then
      raise exception 'Period % of % is closed', v_period.period_no, v_fy.year;
    end if;
    select coalesce(max(entry_no), 0) + 1 into v_next
    from erp.journal_entries where fiscal_year_id = new.fiscal_year_id and id <> new.id;
    if new.entry_no is distinct from v_next then
      raise exception 'The entry number must be the next one in the fiscal year (%): post it with erp.post_entry', v_next;
    end if;
  end if;
  return new;
end $$;

-- ---------- H-079 · La consulta de IA se devuelve si el modelo falla ----------
-- erp.ai_consume da un justificante (call_id) que solo ve la función de Cloudflare; erp.ai_refund lo usa una vez, en
-- los 15 minutos siguientes y solo para su usuario. Nadie lee ni escribe esta tabla directamente.
create table if not exists erp.ai_calls (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null,
  used_on     date not null,
  created_at  timestamptz not null default now(),
  refunded_at timestamptz
);
comment on table erp.ai_calls is 'AI calls charged to the daily quota (v0.60.6): a failed call is refunded once with erp.ai_refund.';
create index if not exists ai_calls_user_idx on erp.ai_calls (user_id, created_at);
alter table erp.ai_calls enable row level security;
revoke all on erp.ai_calls from anon, authenticated;

create or replace function erp.ai_consume(p_company uuid)
returns jsonb language plpgsql security definer set search_path = erp, public set jit = off as $$
declare
  v_limit int;
  v_used  int;
  v_call  uuid;
begin
  if not erp.ai_allowed(p_company) then raise exception 'The AI is not enabled for you in this company'; end if;
  insert into erp.ai_usage (user_id, used_on, calls) values (auth.uid(), current_date, 1)
  on conflict (user_id, used_on) do update set calls = erp.ai_usage.calls + 1
  returning calls into v_used;
  -- v0.60.6 (H-079) · el justificante para devolverla si el modelo falla
  delete from erp.ai_calls where created_at < now() - interval '2 days';
  insert into erp.ai_calls (user_id, used_on) values (auth.uid(), current_date) returning id into v_call;
  if erp.is_owner() then
    return jsonb_build_object('used', v_used, 'limit', null, 'remaining', null, 'call_id', v_call);
  end if;
  v_limit := erp.ai_daily_limit();
  if v_used > v_limit then
    raise exception 'Daily AI limit reached (% per day)', v_limit;
  end if;
  return jsonb_build_object('used', v_used, 'limit', v_limit, 'remaining', v_limit - v_used, 'call_id', v_call);
end $$;

create or replace function erp.ai_refund(p_call uuid)
returns boolean language plpgsql security definer set search_path = erp, public set jit = off as $$
declare v_day date;
begin
  if auth.uid() is null or erp.is_anonymous() then return false; end if;
  update erp.ai_calls set refunded_at = now()
  where id = p_call and user_id = auth.uid() and refunded_at is null and created_at > now() - interval '15 minutes'
  returning used_on into v_day;
  if not found then return false; end if;
  update erp.ai_usage set calls = greatest(calls - 1, 0) where user_id = auth.uid() and used_on = v_day;
  return true;
end $$;
revoke execute on function erp.ai_refund(uuid) from anon, public;
grant execute on function erp.ai_refund(uuid) to authenticated;

-- ---------- H-49 · erp.run_audit_checks, igual que en la 0079, sin la cifra de un diario de estudio en un comentario ----------
CREATE OR REPLACE FUNCTION erp.run_audit_checks(p_company uuid, p_year integer, p_to_date date DEFAULT NULL::date)
 RETURNS TABLE(code text, sort integer, area text, status text, title text, title_en text, why text, why_en text, fix text, fix_en text, screen text, book numeric, ledger numeric, difference numeric, items integer, details jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  v_to     date := coalesce(p_to_date, (select f.ending_date from erp.fiscal_years f where f.company_id = p_company and f.year = p_year));
  v_type   text := (select case c.tax_territory when 'canary_islands' then 'IGIC' else 'VAT' end from erp.companies c where c.id = p_company);
  r        record;
  v_sev    text;
  v_prefix text;
  v_sign   int;
  v_err    boolean;
  v_book numeric; v_ledger numeric; v_items int; v_det jsonb;
  v_al     erp.audit_line[];   -- v0.52.3: los apuntes del ejercicio con su origen, calculados UNA vez para todas
  v_rules  jsonb;   -- v0.52.2: reglas de las cuentas controladas de la empresa
begin
  -- v0.52.3: el permiso, una vez (erp.can_report, como la seguridad fila a fila) y no en cada fila de cada consulta;
  -- todas las consultas de abajo filtran por la empresa
  if not erp.can_report(p_company) then return; end if;
  if v_type is null or v_to is null then return; end if;
  -- v0.52.4: solo los apuntes que usan las comprobaciones (cuentas 47, con impuesto y asientos manuales)
  select array_agg(x) into v_al from erp.audit_lines_checks(p_company, p_year, v_to) x;
  v_al := coalesce(v_al, '{}');     -- empresa o ejercicio que no existe (o no se puede ver)

  for r in select * from erp.audit_checks c order by c.sort loop
    v_book := null; v_ledger := null; v_items := 0; v_det := '[]'; v_sev := r.severity;

    if r.code in ('vat_input', 'vat_output') then
      -- 472 al Debe (soportado) · 477 al Haber (repercutido); sin liquidación ni prorrata
      v_prefix := case r.code when 'vat_input' then '472' else '477' end;
      v_sign   := case r.code when 'vat_input' then 1 else -1 end;
      select coalesce(sum(v_sign * (a.debit - a.credit)) filter (where a.source = 'invoice'), 0),
             coalesce(sum(v_sign * (a.debit - a.credit)), 0)
      into v_book, v_ledger
      from unnest(v_al) a
      where a.account_no like v_prefix || '%' and a.source not in ('settlement', 'pro_rata');
      -- Detalle: asientos manuales o importados (cada uno junto con su contraasiento: si se anularon, no salen)
      with g as (
        select a.k, a.source, min(a.account_no) as account_no, sum(v_sign * (a.debit - a.credit)) as amount
        from unnest(v_al) a
        where a.account_no like v_prefix || '%' and a.source in ('manual', 'import')
        group by a.k, a.source having sum(a.debit - a.credit) <> 0
      ), n as (
        select g.*, e.entry_no, e.posting_date, row_number() over (order by e.posting_date, e.entry_no) as rn
        from g join erp.journal_entries e on e.id = g.k
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('entry_id', n.k, 'entry_no', n.entry_no, 'posting_date', n.posting_date,
                                                   'source', n.source, 'account_no', n.account_no, 'amount', n.amount)
                                order by n.rn) filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'tax_quota' then
      -- v0.33.1: apuntes manuales o importados en 472 / 477 con base y tipo, cuya cuota no es base × tipo
      --   (tolerancia de 1 céntimo por redondeo; un asiento ya anulado no cuenta)
      with x as (
        select e.id as entry_id, e.entry_no, e.posting_date,
               case when e.import_batch_id is not null then 'import' else 'manual' end as source,
               g.account_no, l.tax_code, c.rate_pct, l.tax_base,
               abs(l.debit - l.credit) as amount, round(abs(l.tax_base) * c.rate_pct / 100, 2) as expected
        from erp.journal_lines l
        join erp.journal_entries e on e.id = l.entry_id
        join erp.fiscal_years fy on fy.id = e.fiscal_year_id
        join erp.gl_accounts g on g.id = l.gl_account_id
        join erp.tax_codes c on c.code = l.tax_code
        where e.company_id = p_company and fy.year = p_year and e.status = 'posted' and e.entry_type = 'normal'
          and l.company_id = p_company and g.company_id = p_company and fy.company_id = p_company   -- v0.52.3
          and e.posting_date <= v_to and e.reversal_of is null
          and not exists (select 1 from erp.journal_entries rv
                          where rv.reversal_of = e.id and rv.status = 'posted' and rv.posting_date <= v_to)
          and not exists (select 1 from erp.invoices i where i.entry_id = e.id)
          and (g.account_no like '472%' or g.account_no like '477%')
          and coalesce(l.tax_base, 0) <> 0
      ), n as (
        select x.*, row_number() over (order by x.posting_date, x.entry_no) as rn
        from x where abs(x.amount - x.expected) > 0.01
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('entry_id', n.entry_id, 'entry_no', n.entry_no, 'posting_date', n.posting_date,
                                                   'source', n.source, 'account_no', n.account_no, 'tax_code', n.tax_code,
                                                   'rate_pct', n.rate_pct, 'tax_base', n.tax_base,
                                                   'amount', n.amount, 'expected', n.expected)
                                order by n.rn) filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'withholdings' then
      -- Libro: retenciones practicadas en facturas recibidas (modelos 111 / 115)
      select coalesce(sum(w.withholding_amount), 0) into v_book
      from erp.v_withholding_register w
      where w.company_id = p_company and w.fiscal_year = p_year and w.side = 'withheld' and w.posting_date <= v_to;
      -- v0.38.0: más el IRPF de las nóminas (también va al modelo 111, casillas 01 a 03)
      v_book := v_book + coalesce((select sum(s.irpf) from erp.payslips s
                                   join erp.payroll_runs pr on pr.id = s.run_id
                                   join erp.journal_entries je on je.id = pr.entry_id
                                   join erp.fiscal_years f on f.id = je.fiscal_year_id
                                   where pr.company_id = p_company and pr.status = 'posted' and f.year = p_year and pr.period <= v_to), 0);
      -- Contabilidad: asientos que ABONAN la 4751 (las retenciones). Los que la cargan son el ingreso en Hacienda.
      -- Un contraasiento va con su original (por eso se agrupa por k y el signo es el del original).
      with g as (
        select a.k, a.source, min(a.account_no) as account_no, sum(a.credit - a.debit) as amount,
               (select sum(l.credit - l.debit) from erp.journal_lines l join erp.gl_accounts ga on ga.id = l.gl_account_id
                where l.entry_id = a.k and ga.account_no like '4751%' and ga.account_no not like '47512%') as original
        from unnest(v_al) a
        where a.account_no like '4751%' and a.account_no not like '47512%'   -- v0.42.0: la 47512 (dividendos) va al modelo 123
        group by a.k, a.source
      ), n as (
        select g.*, e.entry_no, e.posting_date,
               row_number() over (order by e.posting_date, e.entry_no) as rn
        from g join erp.journal_entries e on e.id = g.k
        where g.original > 0
      )
      select coalesce(sum(n.amount), 0),
             count(*) filter (where n.source in ('manual', 'import') and n.amount <> 0)::int,
             coalesce(jsonb_agg(jsonb_build_object('entry_id', n.k, 'entry_no', n.entry_no, 'posting_date', n.posting_date,
                                                   'source', n.source, 'account_no', n.account_no, 'amount', n.amount)
                                order by n.rn) filter (where n.source in ('manual', 'import') and n.amount <> 0), '[]')
      into v_ledger, v_items, v_det
      from n;

    elsif r.code = 'tax_forms_settlements' then
      -- v0.39.0 · el resultado de cada modelo trimestral (303 / 420, desde el libro registro) frente a su liquidación
      --   contabilizada (desde la contabilidad): un trimestre liquidado aceptando una diferencia
      with q as (
        select g.q, erp.quarter_end(p_year, g.q) as q_end,
               (select b.amount from erp.tax_form_boxes(p_company, p_year, g.q) b where b.box = case v_type when 'VAT' then '46' else '41' end) as form_result,
               (select s.output_tax - s.input_tax from erp.tax_settlements s where s.company_id = p_company and s.tax_type = v_type
                  and s.year = p_year and s.quarter = g.q and s.status = 'posted') as settled
        from generate_series(1, 4) g(q)
        where erp.quarter_end(p_year, g.q) <= v_to
      ), n as (   -- solo los trimestres liquidados (los que faltan por liquidar los avisa el asistente de cierre)
        select q.*, row_number() over (order by q.q) as rn from q
        where q.settled is not null and q.settled <> q.form_result
      )
      select (select coalesce(sum(form_result), 0) from q where settled is not null), (select coalesce(sum(settled), 0) from q), count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('quarter', n.q, 'form', case v_type when 'VAT' then '303' else '420' end,
                                                   'form_result', n.form_result, 'settled', n.settled, 'amount', coalesce(n.settled, 0) - n.form_result)
                                order by n.rn), '[]')
      into v_book, v_ledger, v_items, v_det
      from n;

    elsif r.code = 'form347_missing_vat' then
      -- v0.39.0 · terceros que hay que declarar en el 347 (más de 3.005,06 € en el año) y no tienen NIF
      with n as (select f.*, row_number() over (order by f.partner_name) as rn from erp.form_347(p_company, p_year) f where f.missing_vat_no)
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('partner_id', n.partner_id, 'partner_name', n.partner_name, 'op_key', n.op_key,
                                                   'amount', n.total) order by n.rn) filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'sources_review' then
      -- v0.39.0 · fuentes oficiales sin revisar en más de un año (las normas y las instrucciones cambian)
      with n as (select s.*, row_number() over (order by s.checked, s.key) as rn from erp.sources s where s.checked < current_date - interval '1 year')
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('key', n.key, 'name', n.title, 'issuer', n.issuer, 'checked', n.checked) order by n.rn), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'partners' then
      with x as (
        select 'purchase' as t, a.* from erp.aging(p_company, 'purchase', v_to) a
        union all
        select 'sale', a.* from erp.aging(p_company, 'sale', v_to) a
      ), d as (
        select x.*, row_number() over (order by abs(x.account_balance - x.total) desc, x.partner_name) as rn
        from x where x.account_balance <> x.total
      )
      select coalesce(sum(d.total), 0), coalesce(sum(d.account_balance), 0), count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('partner_id', d.partner_id, 'partner_name', d.partner_name,
                                                   'account_no', d.partner_account_no, 'invoice_type', d.t,
                                                   'pending', d.total, 'balance', d.account_balance,
                                                   'amount', d.account_balance - d.total)
                                order by d.rn) filter (where d.rn <= 50), '[]')
      into v_book, v_ledger, v_items, v_det
      from d;

    elsif r.code = 'anomalies' then
      select count(*)::int, bool_or(b.severity = 'error'),
             coalesce(jsonb_agg(jsonb_build_object('account_no', b.account_no, 'account_name', b.name, 'expected', b.expected,
                                                   'amount', b.balance, 'reclass_to', b.reclass_to, 'severity', b.severity,
                                                   'note', b.note, 'note_en', b.note_en)), '[]')
      into v_items, v_err, v_det
      from erp.balance_anomalies(p_company, p_year, null, v_to) b;
      if v_err then v_sev := 'error'; end if;
      v_det := coalesce((select jsonb_agg(j.d) from jsonb_array_elements(v_det) with ordinality j(d, n) where j.n <= 50), '[]');

    elsif r.code = 'tax_territory' then
      with g as (
        select a.k, a.source, min(a.account_no) as account_no, min(a.tax_code) as tax_code, sum(a.debit - a.credit) as amount
        from unnest(v_al) a join erp.tax_codes c on c.code = a.tax_code
        where c.tax_type <> v_type
        group by a.k, a.source
        having count(*) filter (where a.entry_id = a.k) > count(*) filter (where a.entry_id <> a.k)  -- sin anular
      ), n as (
        select g.*, e.entry_no, e.posting_date, row_number() over (order by e.posting_date, e.entry_no) as rn
        from g join erp.journal_entries e on e.id = g.k
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('entry_id', n.k, 'entry_no', n.entry_no, 'posting_date', n.posting_date,
                                                   'source', n.source, 'account_no', n.account_no, 'tax_code', n.tax_code,
                                                   'amount', n.amount)
                                order by n.rn) filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'controlled' then
      -- Manuales sin anular que tocan una cuenta controlada; no cuentan los vinculados a un pago (ya están conciliados)
      -- v0.52.2: en bloque (antes, erp.entry_controlled_lines asiento por asiento: 20 s con muchos asientos manuales).
      -- Las reglas de las cuentas de la empresa, en un mapa { cuenta: { modules, side } } (una búsqueda por cuenta), y
      -- cada asiento se queda con su primera línea (por su orden) que toca una cuenta controlada por el lado que controla.
      select coalesce(jsonb_object_agg(d.account_no, jsonb_build_object('modules', to_jsonb(x.modules), 'side', x.side)), '{}')
      into v_rules
      from (select g.account_no from erp.gl_accounts g where g.company_id = p_company) d
      cross join lateral erp.control_rule_for(d.account_no) x
      where x.account_prefix is not null and cardinality(x.modules) > 0;

      with m as (
        select distinct a.entry_id, a.entry_no, a.posting_date
        from unnest(v_al) a
        where a.source = 'manual' and a.entry_id = a.k
      ), hit as (
        select distinct on (m.entry_id) m.entry_id, m.entry_no, m.posting_date, g.account_no,
               v_rules -> g.account_no -> 'modules' as modules
        from m
        join erp.journal_lines l on l.entry_id = m.entry_id
        join erp.gl_accounts g on g.id = l.gl_account_id
        where v_rules ? g.account_no
          and (v_rules -> g.account_no ->> 'side' = 'both'
               or (v_rules -> g.account_no ->> 'side' = 'debit'  and coalesce(l.debit, 0) > 0)
               or (v_rules -> g.account_no ->> 'side' = 'credit' and coalesce(l.credit, 0) > 0))
          and not exists (select 1 from erp.journal_entries x
                          where x.reversal_of = m.entry_id and x.status = 'posted' and x.posting_date <= v_to)
          and not exists (select 1 from erp.payments py where py.entry_id = m.entry_id and py.linked)
        order by m.entry_id, l.line_no
      ), n as (
        select hit.*, row_number() over (order by hit.posting_date, hit.entry_no) as rn from hit
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('entry_id', n.entry_id, 'entry_no', n.entry_no, 'posting_date', n.posting_date,
                                                   'account_no', n.account_no, 'modules', n.modules)
                                order by n.rn) filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'assets_ledger' then
      -- v0.35.0 · cada cuenta de inmovilizado (coste de los activos en uso) y de amortización acumulada (lo amortizado)
      --   frente a su saldo contable a la fecha (sin terrenos 210 / 220, que no tienen ficha amortizable)
      with f as (
        select a.asset_account_id as acc, sum(a.cost) as book from erp.fixed_assets a
        where a.company_id = p_company and (a.status = 'active' or a.disposal_date > v_to) and a.acquisition_date <= v_to
        group by 1
        union all
        select a.depreciation_account_id, -sum(d.amount) from erp.fixed_assets a
        join erp.asset_depreciations d on d.asset_id = a.id and d.period_end <= v_to
        where a.company_id = p_company and (a.status = 'active' or a.disposal_date > v_to)
        group by 1
        union all
        -- v0.37.0 · el deterioro (29x) frente al deterioro neto de las fichas
        select (select jl.gl_account_id from erp.journal_lines jl join erp.gl_accounts g2 on g2.id = jl.gl_account_id
                where jl.entry_id = ev.entry_id and g2.account_no like '29%' limit 1),
               -sum(case ev.kind when 'impairment' then ev.amount else -ev.amount end)
        from erp.asset_events ev join erp.fixed_assets a on a.id = ev.asset_id
        where ev.company_id = p_company and ev.kind in ('impairment', 'reversal') and ev.event_date <= v_to
          and (a.status = 'active' or a.disposal_date > v_to)
        group by 1
      ), l as (
        -- saldo acumulado a la fecha: todos los ejercicios, sin los asientos de cierre ni las aperturas del propio ERP
        -- (repetirían saldos); una apertura IMPORTADA sí cuenta
        select g.id as acc, sum(jl.debit - jl.credit) as ledger
        from erp.journal_lines jl join erp.journal_entries e on e.id = jl.entry_id
        join erp.gl_accounts g on g.id = jl.gl_account_id
        where e.company_id = p_company and e.status = 'posted' and e.posting_date <= v_to and e.entry_type <> 'closing'
          and jl.company_id = p_company and g.company_id = p_company   -- v0.52.3: solo las cuentas y apuntes de la empresa
          and not exists (select 1 from erp.year_closings yc where yc.opening_entry_id = e.id)
          and (left(g.account_no, 2) in ('20', '21', '22', '28') or left(g.account_no, 3) in ('290', '291', '292'))
          and left(g.account_no, 3) not in ('210', '220')
        group by 1
      ), x as (
        select coalesce(f.acc, l.acc) as acc, coalesce(sum(f.book), 0) as book, coalesce(max(l.ledger), 0) as ledger
        from f full join l on l.acc = f.acc group by coalesce(f.acc, l.acc)
      ), n as (
        select g.account_no, g.name, x.book, x.ledger, row_number() over (order by g.account_no) as rn
        from x join erp.gl_accounts g on g.id = x.acc where x.book <> x.ledger
      )
      select coalesce(sum(n.book), 0), coalesce(sum(n.ledger), 0), count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('account_no', n.account_no, 'account_name', n.name, 'book', n.book,
                                                   'balance', n.ledger, 'amount', n.ledger - n.book) order by n.rn)
                      filter (where n.rn <= 50), '[]')
      into v_book, v_ledger, v_items, v_det
      from n;

    elsif r.code = 'assets_pending' then
      -- v0.35.0 · activos con amortización pendiente hasta el último fin de mes de la fecha de corte
      -- (último fin de mes: la propia fecha si es fin de mes; si no, el del mes anterior)
      with c as (select (date_trunc('month', v_to + 1) - interval '1 day')::date as cut),
      p as (
        select a.id, a.code, a.name, a.start_date,
               erp.asset_depr_at(a.id, c.cut) - erp.asset_posted(a.id) as pending,
               (select max(d.period_end) from erp.asset_depreciations d where d.asset_id = a.id) as last_period
        from erp.fixed_assets a cross join c
        where a.company_id = p_company and a.status = 'active'
      ), n as (select p.*, row_number() over (order by p.code) as rn from p where p.pending > 0)
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('asset_id', n.id, 'code', n.code, 'name', n.name, 'amount', n.pending,
                                                   'last_period', n.last_period) order by n.rn) filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'adjustments_ledger' then
      -- v0.36.0 · 480 / 485 / 4009 / 4309 frente a las periodificaciones vivas y 490 frente a los deterioros vivos, a la fecha
      --   (viva: contabilizada hasta la fecha y aún sin revertir, aplicar ni anular a esa fecha)
      with f as (
        select a.balance_account_id as acc,
               sum(case when a.kind in ('prepaid_expense', 'accrued_income') then a.amount else -a.amount end) as book
        from erp.accruals a
        where a.company_id = p_company and a.cutoff_date <= v_to
          and (a.reversal_date is null or a.reversal_date > v_to)
          and (a.cancel_entry_id is null or (select ce.posting_date from erp.journal_entries ce where ce.id = a.cancel_entry_id) > v_to)
        group by 1
        union all
        select (select g.id from erp.gl_accounts g join erp.journal_lines jl on jl.gl_account_id = g.id
                where jl.entry_id = i.entry_id and g.account_no like '490%' limit 1), -sum(i.amount)
        from erp.receivable_impairments i
        where i.company_id = p_company and i.impair_date <= v_to
          and (i.end_date is null or i.end_date > v_to)
          and (i.cancel_entry_id is null or (select ce.posting_date from erp.journal_entries ce where ce.id = i.cancel_entry_id) > v_to)
        group by 1
      ), l as (
        -- saldo acumulado a la fecha (todos los ejercicios, sin cierres ni aperturas del propio ERP), como assets_ledger
        select g.id as acc, sum(jl.debit - jl.credit) as ledger
        from erp.journal_lines jl join erp.journal_entries e on e.id = jl.entry_id
        join erp.gl_accounts g on g.id = jl.gl_account_id
        where e.company_id = p_company and e.status = 'posted' and e.posting_date <= v_to and e.entry_type <> 'closing'
          and jl.company_id = p_company and g.company_id = p_company   -- v0.52.3: solo las cuentas y apuntes de la empresa
          and not exists (select 1 from erp.year_closings yc where yc.opening_entry_id = e.id)
          and (g.account_no like '480%' or g.account_no like '485%' or g.account_no like '4009%'
               or g.account_no like '4309%' or g.account_no like '490%')
        group by 1
      ), x as (
        select coalesce(f.acc, l.acc) as acc, coalesce(sum(f.book), 0) as book, coalesce(max(l.ledger), 0) as ledger
        from f full join l on l.acc = f.acc group by coalesce(f.acc, l.acc)
      ), n as (
        select g.account_no, g.name, x.book, x.ledger, row_number() over (order by g.account_no) as rn
        from x join erp.gl_accounts g on g.id = x.acc where x.book <> x.ledger
      )
      select coalesce(sum(n.book), 0), coalesce(sum(n.ledger), 0), count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('account_no', n.account_no, 'account_name', n.name, 'book', n.book,
                                                   'balance', n.ledger, 'amount', n.ledger - n.book) order by n.rn)
                      filter (where n.rn <= 50), '[]')
      into v_book, v_ledger, v_items, v_det
      from n;

    elsif r.code = 'accruals_unreversed' then
      -- v0.36.0 · periodificaciones de un ejercicio anterior que siguen sin revertir en este
      with fy as (select f.starting_date from erp.fiscal_years f where f.company_id = p_company and f.year = p_year),
      n as (
        select a.id, a.code, a.description, a.cutoff_date, a.amount, row_number() over (order by a.code) as rn
        from erp.accruals a cross join fy
        where a.company_id = p_company and a.status = 'active' and a.cutoff_date < fy.starting_date and fy.starting_date <= v_to
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('accrual_id', n.id, 'code', n.code, 'name', n.description,
                                                   'cutoff_date', n.cutoff_date, 'amount', n.amount) order by n.rn)
                      filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code in ('provisions_ledger', 'inventory_ledger', 'payroll_ledger', 'financing_ledger', 'grants_ledger') then
      -- v0.37.0 · las cuentas de provisiones (141 / 142 / 5292 / 5293 / 499) y de existencias (30-36 / 39) frente a lo
      --   que han contabilizado sus módulos: la diferencia es un asiento manual o un saldo importado sin su ficha
      with lm as (
        select g.id as acc, sum(jl.debit - jl.credit) as amount,
               bool_or(exists (select 1 from erp.provision_movements pm where pm.entry_id = e.id)
                       or exists (select 1 from erp.inventory_counts ic where ic.entry_id = e.id and ic.status = 'posted')
                       -- v0.38.0: la nómina y sus pagos
                       or exists (select 1 from erp.payroll_runs pr where e.id in (pr.entry_id, pr.net_payment_entry_id, pr.ss_payment_entry_id))
                       -- v0.43.0: los préstamos y el leasing (también la factura de la cuota)
                       or exists (select 1 from erp.loan_events le where le.entry_id = e.id and le.status = 'posted')
                       -- v0.44.0: las subvenciones, y la regularización de los grupos 8 y 9 contra la 130 del cierre
                       or exists (select 1 from erp.grant_events ge where ge.entry_id = e.id and ge.status = 'posted')
                       or e.entry_type = 'closing_pl') as module
        from erp.journal_lines jl join erp.journal_entries e on e.id = jl.entry_id
        join erp.gl_accounts g on g.id = jl.gl_account_id
        where e.company_id = p_company and e.status = 'posted' and e.posting_date <= v_to and e.entry_type <> 'closing'
          and jl.company_id = p_company and g.company_id = p_company   -- v0.52.3: solo las cuentas y apuntes de la empresa
          and not exists (select 1 from erp.year_closings yc where yc.opening_entry_id = e.id)
          and case r.code when 'provisions_ledger' then g.account_no ~ '^(141|142|5292|5293|499)'
                          when 'payroll_ledger' then g.account_no ~ '^(465|476)'   -- v0.38.0
                          when 'financing_ledger' then g.account_no ~ '^(170|171|174|520|521|524|527|528)'   -- v0.43.0
                          when 'grants_ledger' then g.account_no ~ '^(13[0-2]|172|522|4708|8|9)'   -- v0.44.0
                          else g.account_no ~ '^3[0-6]|^39' end
          -- un movimiento anulado y su contraasiento se compensan: ninguno de los dos cuenta como del módulo
          and not (e.reversal_of is not null or e.reversed_by is not null)
        group by g.id, e.id
      ), x as (
        select acc, coalesce(sum(amount) filter (where module), 0) as book, sum(amount) as ledger from lm group by acc
      ), n as (
        select g.account_no, g.name, x.book, x.ledger, row_number() over (order by g.account_no) as rn
        from x join erp.gl_accounts g on g.id = x.acc where x.book <> x.ledger
      )
      select coalesce(sum(n.book), 0), coalesce(sum(n.ledger), 0), count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('account_no', n.account_no, 'account_name', n.name, 'book', n.book,
                                                   'balance', n.ledger, 'amount', n.ledger - n.book) order by n.rn)
                      filter (where n.rn <= 50), '[]')
      into v_book, v_ledger, v_items, v_det
      from n;

    elsif r.code = 'provisions_review' then
      -- v0.37.0 · al cierre, provisiones vivas sin revisar en el ejercicio (NRV 15.ª: se revisan en cada cierre)
      with fy as (select f.starting_date, f.ending_date from erp.fiscal_years f where f.company_id = p_company and f.year = p_year),
      n as (
        select pv.id, pv.code, pv.description, erp.provision_balance(pv.id) as balance,
               (select max(m.movement_date) from erp.provision_movements m where m.provision_id = pv.id) as last_date,
               row_number() over (order by pv.code) as rn
        from erp.provisions pv cross join fy
        where pv.company_id = p_company and pv.status = 'active' and v_to >= fy.ending_date
          and exists (select 1 from erp.provision_movements m where m.provision_id = pv.id and m.movement_date < fy.starting_date)
          and not exists (select 1 from erp.provision_movements m where m.provision_id = pv.id
                          and m.movement_date between fy.starting_date and fy.ending_date)
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('provision_id', n.id, 'code', n.code, 'name', n.description,
                                                   'amount', n.balance, 'last_date', n.last_date) order by n.rn)
                      filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'impairments_collected' then
      -- v0.36.0 · deterioro individual vivo de una factura que ya no tiene nada pendiente (cobrada o rectificada)
      with n as (
        select i.id, i.code, i.amount, o.invoice_no, o.partner_name, row_number() over (order by i.code) as rn
        from erp.receivable_impairments i
        join erp.open_items(p_company, v_to) o on o.invoice_id = i.invoice_id
        where i.company_id = p_company and i.method = 'individual' and i.status = 'active' and i.impair_date <= v_to
          and o.pending <= 0
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('impairment_id', n.id, 'code', n.code, 'invoice_no', n.invoice_no,
                                                   'partner_name', n.partner_name, 'amount', n.amount) order by n.rn)
                      filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;
    end if;

    code := r.code; sort := r.sort; area := r.area;
    status := case when coalesce(v_ledger, 0) = coalesce(v_book, 0) and v_items = 0 then 'ok' else v_sev end;
    title := r.title; title_en := r.title_en; why := r.why; why_en := r.why_en; fix := r.fix; fix_en := r.fix_en;
    screen := r.screen; book := v_book; ledger := v_ledger;
    difference := case when v_book is null then null else v_ledger - v_book end;
    items := v_items; details := v_det;
    return next;
  end loop;
end $function$
;
