-- =====================================================================
-- 0062 · FINANCIACIÓN (I): préstamos a coste amortizado y arrendamiento financiero · v0.43.0
-- ---------------------------------------------------------------------
-- Los pasivos financieros a coste amortizado (PGC, NRV 9.ª, apdo. 3.1) y el arrendamiento financiero del arrendatario
-- (NRV 8.ª, apdo. 1.1), con su cuadro de amortización y sus asientos:
--   · Préstamo (sistema francés, cuota constante; mensual, trimestral, semestral o anual): la cuota sale del tipo
--     nominal; si hay comisiones o gastos, el cuadro se calcula con el TIPO DE INTERÉS EFECTIVO, el que iguala lo
--     recibido con las cuotas (los gastos van dentro de los intereses, nunca como gasto del primer día).
--     Alta: 572 / 5200 (lo que baja la deuda en los 12 meses siguientes) + 1700 (el resto). Cuota: 6623 + 5200 / 572.
--   · Arrendamiento financiero: el activo y la deuda, por el menor del valor razonable y el valor actual de los pagos
--     (cuotas + opción de compra); el tipo implícito los iguala. Alta: 213 / 5240 + 1740. Las cuotas, con su IVA, se
--     registran como factura recibida de la entidad (0063): aquí, la propuesta de cada cuota.
--   · Cierre: los intereses devengados y no vencidos (6623 / 527, con el TIE: compuesto, base 30/360) y la
--     reclasificación del largo al corto plazo (1700 → 5200 y 1740 → 5240) de lo que vence en los 12 meses siguientes.
-- Cada préstamo es un módulo propio: sus asientos no se anulan desde el diario; se deshacen desde su pantalla, del
-- último al primero. Las cuentas se pueden compartir entre préstamos: lo que es de cada uno lo llevan sus movimientos.
-- Supuestos de referencia: supuestos-v0.43.0.md (F1, F1b, F2 y F3). Re-ejecutable.
-- =====================================================================

-- 1) Los préstamos y los arrendamientos financieros
create table if not exists erp.loans (
  id                  uuid primary key default gen_random_uuid(),
  company_id          uuid not null references erp.companies(id) on delete cascade,
  code                text not null,                      -- FIN-0001…
  kind                text not null check (kind in ('loan', 'leasing')),
  description         text not null,
  lender              text not null default '',
  lender_type         text not null default 'bank' check (lender_type in ('bank', 'other')),
  start_date          date not null,
  first_due_date      date not null,
  frequency           int  not null check (frequency in (1, 2, 4, 12)),   -- cuotas al año
  periods             int  not null check (periods between 1 and 600),
  nominal_rate        numeric(9,4) not null default 0,   -- % anual (préstamo: el del contrato; leasing: el del contrato, si se dio)
  principal           numeric(14,2) not null,            -- préstamo: el nominal · leasing: el valor reconocido
  costs               numeric(14,2) not null default 0,  -- comisiones y gastos del préstamo
  net_amount          numeric(14,2) not null,            -- coste amortizado inicial (lo recibido)
  instalment          numeric(14,2) not null,            -- cuota (sin IVA)
  purchase_option     numeric(14,2) not null default 0,
  fair_value          numeric(14,2),
  present_value       numeric(14,2),                     -- leasing: valor actual de los pagos al tipo del contrato
  effective_rate      numeric not null,                  -- TIE de cada periodo (tanto por uno)
  effective_rate_year numeric(12,6) not null,            -- TIE anual en %
  long_account_id     uuid not null references erp.gl_accounts(id),
  short_account_id    uuid not null references erp.gl_accounts(id),
  interest_account_id uuid not null references erp.gl_accounts(id),
  accrued_account_id  uuid not null references erp.gl_accounts(id),
  bank_account_id     uuid references erp.gl_accounts(id),
  asset_account_id    uuid references erp.gl_accounts(id),
  status              text not null default 'active' check (status in ('active', 'repaid', 'cancelled')),
  data                jsonb not null default '{}',
  created_at          timestamptz not null default now(),
  unique (company_id, code)
);
comment on table erp.loans is 'Loans at amortised cost (PGC NRV 9) and finance leases of the lessee (NRV 8), with their amortisation schedule.';
create index if not exists loans_company_idx on erp.loans (company_id, start_date);

create table if not exists erp.loan_schedule (
  loan_id    uuid not null references erp.loans(id) on delete cascade,
  company_id uuid not null references erp.companies(id) on delete cascade,
  n          int  not null,
  due_date   date not null,
  payment    numeric(14,2) not null,   -- lo que se paga (leasing: la cuota sin IVA y, en la última, la opción)
  interest   numeric(14,2) not null,   -- intereses al TIE
  reduction  numeric(14,2) not null,   -- lo que baja el coste amortizado
  balance    numeric(14,2) not null,   -- coste amortizado después de pagar
  primary key (loan_id, n)
);
comment on table erp.loan_schedule is 'Amortisation schedule of a loan or finance lease, at the effective interest rate.';

create table if not exists erp.loan_events (
  id           uuid primary key default gen_random_uuid(),
  seq          bigserial,
  loan_id      uuid not null references erp.loans(id) on delete cascade,
  company_id   uuid not null references erp.companies(id) on delete cascade,
  kind         text not null check (kind in ('start', 'payment', 'accrual', 'reclassification')),
  event_date   date not null,
  n            int,                                  -- la cuota (pago y devengo)
  amount       numeric(14,2) not null default 0,     -- pago: la cuota · devengo: los intereses · reclasificación: lo que pasa a corto (± )
  interest     numeric(14,2) not null default 0,     -- pago: intereses que van a gasto en el asiento
  accrued_used numeric(14,2) not null default 0,     -- pago: intereses ya devengados (527 / 528) que se pagan
  short_part   numeric(14,2) not null default 0,     -- alta: parte a corto · pago: lo que baja la deuda a corto
  long_part    numeric(14,2) not null default 0,     -- alta: parte a largo · pago: lo que baja la deuda a largo
  entry_id     uuid references erp.journal_entries(id),
  invoice_id   uuid,                                 -- leasing: la factura de la cuota (0063)
  status       text not null default 'posted' check (status in ('posted', 'cancelled')),
  created_at   timestamptz not null default now()
);
comment on table erp.loan_events is 'Postings of a loan or finance lease: start, instalments, year-end accrued interest and long-to-short reclassification.';
create index if not exists loan_events_loan_idx on erp.loan_events (loan_id, seq);
create index if not exists loan_events_entry_idx on erp.loan_events (entry_id);
-- las claves foráneas, con su índice (fase 23)
create index if not exists loans_long_account_idx     on erp.loans (long_account_id);
create index if not exists loans_short_account_idx    on erp.loans (short_account_id);
create index if not exists loans_interest_account_idx on erp.loans (interest_account_id);
create index if not exists loans_accrued_account_idx  on erp.loans (accrued_account_id);
create index if not exists loans_bank_account_idx     on erp.loans (bank_account_id);
create index if not exists loans_asset_account_idx    on erp.loans (asset_account_id);
create index if not exists loan_schedule_company_idx  on erp.loan_schedule (company_id);
create index if not exists loan_events_company_idx    on erp.loan_events (company_id);

alter table erp.loans enable row level security;
alter table erp.loan_schedule enable row level security;
alter table erp.loan_events enable row level security;
drop policy if exists read on erp.loans;
create policy read on erp.loans for select to authenticated using (erp.can_read(company_id));
drop policy if exists read on erp.loan_schedule;
create policy read on erp.loan_schedule for select to authenticated using (erp.can_read(company_id));
drop policy if exists read on erp.loan_events;
create policy read on erp.loan_events for select to authenticated using (erp.can_read(company_id));
revoke all on erp.loans, erp.loan_schedule, erp.loan_events from anon, public;
grant select on erp.loans, erp.loan_schedule, erp.loan_events to authenticated;   -- se escriben con las funciones

-- 2) Cálculo financiero
-- Días entre dos fechas en base 30/360 (europea): cada mes cuenta 30 días. Con ella, de un 01/07 al 01/01 hay 180
-- días, medio año exacto, como en los manuales.
create or replace function erp.loan_days360(p_from date, p_to date)
returns int language sql immutable as $$
  select (extract(year from p_to)::int - extract(year from p_from)::int) * 360
       + (extract(month from p_to)::int - extract(month from p_from)::int) * 30
       + (least(extract(day from p_to)::int, 30) - least(extract(day from p_from)::int, 30));
$$;

-- Pagos del sistema francés al tipo de cada periodo (tanto por uno): cuota redondeada al céntimo; la última ajusta el
-- redondeo (lo pendiente + sus intereses)
create or replace function erp.loan_french_payments(p_principal numeric, p_rate numeric, p_n int)
returns numeric[] language plpgsql immutable as $$
declare v_pay numeric; v_bal numeric := p_principal; v_int numeric; r numeric[] := '{}'; t int;
begin
  v_pay := case when p_rate = 0 then round(p_principal / p_n, 2)
                else round(p_principal * p_rate / (1 - power(1 + p_rate, -p_n)), 2) end;
  for t in 1..p_n loop
    v_int := round(v_bal * p_rate, 2);
    if t = p_n then r := r || (v_bal + v_int); else r := r || v_pay; v_bal := v_bal - (v_pay - v_int); end if;
  end loop;
  return r;
end $$;

-- Valor actual de unos pagos (uno al final de cada periodo) a un tipo por periodo
create or replace function erp.loan_present_value(p_pays numeric[], p_rate numeric)
returns numeric language plpgsql immutable as $$
declare v numeric := 1; d numeric := round(1 / (1 + p_rate), 30); s numeric := 0; x numeric;
begin
  foreach x in array p_pays loop
    v := round(v * d, 30);
    s := s + x * v;
  end loop;
  return s;
end $$;

-- Tipo de interés efectivo por periodo: el que iguala lo recibido con los pagos (como TIR de una hoja de cálculo;
-- por bisección, con 30 decimales)
create or replace function erp.loan_effective_rate(p_pays numeric[], p_net numeric)
returns numeric language plpgsql immutable as $$
declare lo numeric := 0; hi numeric := 1; m numeric; k int;
begin
  if p_net <= 0 then raise exception 'The amount received must be positive'; end if;
  if (select sum(x) from unnest(p_pays) x) < p_net then raise exception 'The payments are lower than the amount received'; end if;
  if (select sum(x) from unnest(p_pays) x) = p_net then return 0; end if;
  for k in 1..110 loop
    m := round((lo + hi) / 2, 32);
    if erp.loan_present_value(p_pays, m) > p_net then lo := m; else hi := m; end if;
  end loop;
  return round((lo + hi) / 2, 30);
end $$;

-- Cuadro a coste amortizado: intereses = TIE × lo pendiente (al céntimo); en la última cuota, lo que falta para dejar
-- la deuda a cero
create or replace function erp.loan_rows(p_pays numeric[], p_net numeric, p_rate numeric)
returns table (n int, payment numeric, interest numeric, reduction numeric, balance numeric)
language plpgsql immutable as $$
declare v_bal numeric := p_net; t int; k int := array_length(p_pays, 1);
begin
  for t in 1..k loop
    n := t; payment := p_pays[t];
    interest := case when t = k then p_pays[t] - v_bal else round(v_bal * p_rate, 2) end;
    reduction := payment - interest;
    v_bal := v_bal - reduction; balance := v_bal;
    return next;
  end loop;
end $$;

-- 3) Ayudas
-- Una cuenta del préstamo: la pedida (tiene que empezar por uno de los prefijos permitidos y ser de movimientos) o la
-- primera subcuenta del prefijo por defecto (si no hay, se crea)
create or replace function erp.loan_account(p_company uuid, p_no text, p_default text, p_name text, p_allowed text)
returns uuid language plpgsql security definer set search_path = erp, public as $$
declare v uuid;
begin
  if nullif(btrim(p_no), '') is not null then
    select id into v from erp.gl_accounts
    where company_id = p_company and account_no = btrim(p_no) and account_type = 'posting' and account_no ~ p_allowed;
    if v is null then raise exception 'Account % does not exist or is not valid here (%)', p_no, p_allowed; end if;
    return v;
  end if;
  return erp.adjust_account(p_company, p_default, p_name);
end $$;

create or replace function erp.loan_check(p_company uuid, p_date date)
returns void language plpgsql security definer set search_path = erp, public as $$
declare v_fy erp.fiscal_years;
begin
  if not erp.can_write(p_company) then raise exception 'No permission to post loans in this company'; end if;
  if p_date is null then raise exception 'The date is required'; end if;
  select * into v_fy from erp.fiscal_years where company_id = p_company and p_date between starting_date and ending_date;
  if not found then raise exception 'No fiscal year for date %: create it first', p_date; end if;
  if v_fy.status = 'closed' then raise exception 'Fiscal year % is closed', v_fy.year; end if;
  perform pg_advisory_xact_lock(hashtext('loans/' || p_company));
end $$;

-- Lo que el préstamo tiene hoy en cada cuenta (según sus movimientos)
create or replace function erp.loan_position(p_loan uuid)
returns jsonb language sql stable security definer set search_path = erp, public as $$
  select jsonb_build_object(
    'short', coalesce(sum(case kind when 'start' then short_part when 'reclassification' then amount when 'payment' then -short_part else 0 end), 0),
    'long',  coalesce(sum(case kind when 'start' then long_part when 'reclassification' then -amount when 'payment' then -long_part else 0 end), 0),
    'accrued', coalesce(sum(case kind when 'accrual' then amount when 'payment' then -accrued_used else 0 end), 0),
    'paid', coalesce(max(n) filter (where kind = 'payment'), 0))
  from erp.loan_events where loan_id = p_loan and status = 'posted';
$$;

-- Lo que debería estar a corto a una fecha: lo que baja la deuda en las cuotas sin pagar que vencen en los 12 meses
-- siguientes (o ya han vencido)
create or replace function erp.loan_short_target(p_loan uuid, p_date date)
returns numeric language sql stable security definer set search_path = erp, public as $$
  select coalesce(sum(s.reduction), 0) from erp.loan_schedule s
  where s.loan_id = p_loan and s.n > (erp.loan_position(p_loan)->>'paid')::int and s.due_date <= p_date + interval '1 year';
$$;

-- Intereses devengados y no vencidos de la cuota siguiente a una fecha (con el TIE: lo pendiente × ((1 + TIE)^f − 1),
-- f = la parte del periodo que ha pasado, base 30/360), menos lo ya devengado de esa cuota
create or replace function erp.loan_accrual_amount(p_loan uuid, p_date date)
returns jsonb language plpgsql stable security definer set search_path = erp, public as $$
declare
  l erp.loans; v_paid int; s erp.loan_schedule; v_from date; v_bal numeric; f numeric; v_total numeric; v_done numeric;
begin
  select * into l from erp.loans where id = p_loan;
  v_paid := (erp.loan_position(p_loan)->>'paid')::int;
  select * into s from erp.loan_schedule where loan_id = p_loan and n = v_paid + 1;
  if not found or l.start_date > p_date then return null; end if;
  if s.due_date <= p_date then
    return jsonb_build_object('n', s.n, 'amount', 0, 'overdue', true, 'due_date', s.due_date);
  end if;
  if v_paid = 0 then v_from := l.start_date; v_bal := l.net_amount;
  else
    select due_date + 1, balance into v_from, v_bal from erp.loan_schedule where loan_id = p_loan and n = v_paid;
  end if;
  f := least(1, greatest(0, erp.loan_days360(v_from, p_date + 1)::numeric / (360 / l.frequency)));
  v_total := least(s.interest, round(v_bal * (power(1 + l.effective_rate, f) - 1), 2));
  select coalesce(sum(amount), 0) into v_done from erp.loan_events where loan_id = p_loan and kind = 'accrual' and n = s.n and status = 'posted';
  return jsonb_build_object('n', s.n, 'amount', greatest(0, v_total - v_done), 'fraction', round(f, 6), 'days', erp.loan_days360(v_from, p_date + 1),
                            'overdue', false, 'due_date', s.due_date);
end $$;

-- 4) Calcular (sin grabar): p = préstamo { kind: 'loan', principal, rate (% anual), periods, frequency (12), costs?,
--    start_date, first_due_date? (por defecto, un periodo después menos un día) } · leasing { kind: 'leasing',
--    fair_value, instalment, periods, frequency, purchase_option?, rate? (% anual del contrato), start_date, first_due_date? }
create or replace function erp.loan_calc(p jsonb)
returns jsonb language plpgsql stable as $$
declare
  v_kind text := coalesce(p->>'kind', 'loan'); v_freq int := coalesce((p->>'frequency')::int, 12); v_n int := (p->>'periods')::int;
  v_start date := (p->>'start_date')::date; v_first date; v_rate numeric := coalesce((p->>'rate')::numeric, 0);
  v_months int; v_pays numeric[]; v_principal numeric; v_costs numeric := round(coalesce((p->>'costs')::numeric, 0), 2);
  v_net numeric; v_inst numeric; v_opt numeric := round(coalesce((p->>'purchase_option')::numeric, 0), 2);
  v_fv numeric; v_pv numeric; v_eff numeric; v_rows jsonb;
begin
  if v_kind not in ('loan', 'leasing') then raise exception 'Invalid kind: %', v_kind; end if;
  if v_freq not in (1, 2, 4, 12) then raise exception 'The frequency must be 1, 2, 4 or 12 instalments a year'; end if;
  if v_n is null or v_n < 1 or v_n > 600 then raise exception 'The number of instalments must be between 1 and 600'; end if;
  if v_start is null then raise exception 'The start date is required'; end if;
  if v_rate < 0 or v_rate > 100 then raise exception 'The interest rate must be between 0 and 100'; end if;
  v_months := 12 / v_freq;
  v_first := coalesce((p->>'first_due_date')::date, (v_start + make_interval(months => v_months))::date - 1);
  if v_first <= v_start or v_first > v_start + make_interval(months => v_months) then
    raise exception 'The first instalment must fall within the first period after the start date';
  end if;
  if v_kind = 'loan' then
    v_principal := round(coalesce((p->>'principal')::numeric, 0), 2);
    if v_principal <= 0 then raise exception 'The loan amount must be positive'; end if;
    if v_costs < 0 or v_costs >= v_principal then raise exception 'The costs must be between 0 and the loan amount'; end if;
    v_pays := erp.loan_french_payments(v_principal, v_rate / 100 / v_freq, v_n);
    v_net := v_principal - v_costs;
    v_eff := case when v_costs = 0 then v_rate / 100 / v_freq else erp.loan_effective_rate(v_pays, v_net) end;
    v_inst := v_pays[1];
  else
    v_fv := round(coalesce((p->>'fair_value')::numeric, 0), 2); v_inst := round(coalesce((p->>'instalment')::numeric, 0), 2);
    if v_fv <= 0 or v_inst <= 0 then raise exception 'The fair value and the instalment must be positive'; end if;
    if v_opt < 0 then raise exception 'The purchase option cannot be negative'; end if;
    select array_agg(case when t = v_n then v_inst + v_opt else v_inst end order by t) into v_pays from generate_series(1, v_n) t;
    if p ? 'rate' and v_rate > 0 then v_pv := round(erp.loan_present_value(v_pays, v_rate / 100 / v_freq), 2); end if;
    v_net := least(v_fv, coalesce(v_pv, v_fv));   -- NRV 8.ª: el menor
    v_principal := v_net;
    v_eff := erp.loan_effective_rate(v_pays, v_net);
  end if;
  select jsonb_agg(jsonb_build_object('n', r.n, 'due_date', (v_first + make_interval(months => v_months * (r.n - 1)))::date,
                                      'payment', r.payment, 'interest', r.interest, 'reduction', r.reduction, 'balance', r.balance) order by r.n)
  into v_rows from erp.loan_rows(v_pays, v_net, v_eff) r;
  return jsonb_build_object(
    'kind', v_kind, 'frequency', v_freq, 'periods', v_n, 'start_date', v_start, 'first_due_date', v_first,
    'nominal_rate', v_rate, 'principal', v_principal, 'costs', v_costs, 'net_amount', v_net, 'instalment', v_inst,
    'purchase_option', v_opt, 'fair_value', v_fv, 'present_value', v_pv,
    'effective_rate', v_eff, 'effective_rate_year', round((power(1 + v_eff, v_freq) - 1) * 100, 6),
    'total_interest', (select sum((x->>'interest')::numeric) from jsonb_array_elements(v_rows) x),
    'short_part', (select coalesce(sum((x->>'reduction')::numeric), 0) from jsonb_array_elements(v_rows) x
                   where (x->>'due_date')::date <= v_start + interval '1 year'),
    'schedule', v_rows);
end $$;

-- 5) Alta: calcula, graba el cuadro y contabiliza el cobro (préstamo) o el alta del activo (leasing)
--    p = lo de loan_calc + { company_id, description, lender?, lender_type? ('bank' | 'other'), bank_account_no?,
--    long_account_no?, short_account_no?, interest_account_no?, asset_account_no? (leasing; por defecto, 213) }
create or replace function erp.loan_create(p jsonb)
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare
  v_company uuid := (p->>'company_id')::uuid; c jsonb; v_code text; v_id uuid; v_type text := coalesce(p->>'lender_type', 'bank');
  v_desc text := nullif(btrim(p->>'description'), ''); a_long uuid; a_short uuid; a_int uuid; a_acc uuid; a_bank uuid; a_asset uuid;
  v_short numeric; v_long numeric; v_entry uuid;
begin
  c := erp.loan_calc(p);
  perform erp.loan_check(v_company, (c->>'start_date')::date);
  if v_desc is null then raise exception 'The description is required'; end if;
  if v_type not in ('bank', 'other') then raise exception 'Invalid lender type: %', v_type; end if;
  if c->>'kind' = 'loan' then
    a_long  := erp.loan_account(v_company, p->>'long_account_no', case v_type when 'bank' then '1700' else '1710' end,
                 case v_type when 'bank' then 'Préstamos a largo plazo de entidades de crédito' else 'Deudas a largo plazo' end, '^17[01]');
    a_short := erp.loan_account(v_company, p->>'short_account_no', case v_type when 'bank' then '5200' else '5210' end,
                 case v_type when 'bank' then 'Préstamos a corto plazo de entidades de crédito' else 'Deudas a corto plazo' end, '^52[01]');
    a_bank  := erp.equity_bank(v_company, p->>'bank_account_no');
  else
    a_long  := erp.loan_account(v_company, p->>'long_account_no', '1740', 'Acreedores por arrendamiento financiero a largo plazo', '^174');
    a_short := erp.loan_account(v_company, p->>'short_account_no', '5240', 'Acreedores por arrendamiento financiero a corto plazo', '^524');
    a_asset := erp.loan_account(v_company, p->>'asset_account_no', '213', 'Maquinaria', '^2[01]');
    if nullif(btrim(p->>'bank_account_no'), '') is not null then a_bank := erp.equity_bank(v_company, p->>'bank_account_no'); end if;
  end if;
  a_int := erp.loan_account(v_company, p->>'interest_account_no', case v_type when 'bank' then '6623' else '6624' end,
             case v_type when 'bank' then 'Intereses de deudas con entidades de crédito' else 'Intereses de deudas con otras empresas' end, '^662');
  a_acc := erp.adjust_account(v_company, case v_type when 'bank' then '527' else '528' end,
             case v_type when 'bank' then 'Intereses a corto plazo de deudas con entidades de crédito' else 'Intereses a corto plazo de deudas' end);
  select 'FIN-' || lpad((count(*) + 1)::text, 4, '0') into v_code from erp.loans where company_id = v_company;
  insert into erp.loans (company_id, code, kind, description, lender, lender_type, start_date, first_due_date, frequency, periods,
                         nominal_rate, principal, costs, net_amount, instalment, purchase_option, fair_value, present_value,
                         effective_rate, effective_rate_year, long_account_id, short_account_id, interest_account_id,
                         accrued_account_id, bank_account_id, asset_account_id, data)
  values (v_company, v_code, c->>'kind', v_desc, coalesce(btrim(p->>'lender'), ''), v_type, (c->>'start_date')::date, (c->>'first_due_date')::date,
          (c->>'frequency')::int, (c->>'periods')::int, (c->>'nominal_rate')::numeric, (c->>'principal')::numeric, (c->>'costs')::numeric,
          (c->>'net_amount')::numeric, (c->>'instalment')::numeric, (c->>'purchase_option')::numeric, (c->>'fair_value')::numeric,
          (c->>'present_value')::numeric, (c->>'effective_rate')::numeric, (c->>'effective_rate_year')::numeric,
          a_long, a_short, a_int, a_acc, a_bank, a_asset, p - 'company_id')
  returning id into v_id;
  insert into erp.loan_schedule (loan_id, company_id, n, due_date, payment, interest, reduction, balance)
  select v_id, v_company, (x->>'n')::int, (x->>'due_date')::date, (x->>'payment')::numeric, (x->>'interest')::numeric,
         (x->>'reduction')::numeric, (x->>'balance')::numeric
  from jsonb_array_elements(c->'schedule') x;
  v_short := (c->>'short_part')::numeric; v_long := (c->>'net_amount')::numeric - v_short;
  v_entry := erp.equity_entry(v_company, (c->>'start_date')::date,
               case c->>'kind' when 'loan' then 'Préstamo · cobro' else 'Arrendamiento financiero · alta del activo' end || ' · ' || v_desc, v_code,
               jsonb_build_array(erp.equity_line(coalesce(a_asset, a_bank), (c->>'net_amount')::numeric, 0),
                                 erp.equity_line(a_short, 0, v_short), erp.equity_line(a_long, 0, v_long)));
  insert into erp.loan_events (loan_id, company_id, kind, event_date, amount, short_part, long_part, entry_id)
  values (v_id, v_company, 'start', (c->>'start_date')::date, (c->>'net_amount')::numeric, v_short, v_long, v_entry);
  return (c - 'schedule') || jsonb_build_object('loan_id', v_id, 'code', v_code,
    'entry_no', (select entry_no from erp.journal_entries where id = v_entry));
end $$;

-- 6) Lo que lleva la cuota siguiente: intereses (los ya devengados, a la 527 / 528; el resto, a gasto) y lo que baja
--    la deuda (de la parte a corto y, si no alcanza, de la de largo). La usa el pago del préstamo y, en el leasing, la
--    factura de la entidad (0063).
create or replace function erp.loan_next_instalment(p_loan uuid)
returns jsonb language plpgsql stable security definer set search_path = erp, public as $$
declare l erp.loans; pos jsonb; s erp.loan_schedule; v_acc numeric; v_short numeric;
begin
  select * into l from erp.loans where id = p_loan;
  if not found then raise exception 'Loan not found'; end if;
  if not erp.can_read(l.company_id) then raise exception 'No permission to read this company'; end if;
  pos := erp.loan_position(p_loan);
  select * into s from erp.loan_schedule where loan_id = p_loan and n = (pos->>'paid')::int + 1;
  if not found then return null; end if;
  v_acc := least(s.interest, (pos->>'accrued')::numeric);
  v_short := least(s.reduction, greatest(0, (pos->>'short')::numeric));
  return jsonb_build_object('loan_id', p_loan, 'code', l.code, 'kind', l.kind, 'n', s.n, 'periods', l.periods, 'due_date', s.due_date,
    'payment', s.payment, 'interest', s.interest, 'interest_expense', s.interest - v_acc, 'accrued_used', v_acc,
    'reduction', s.reduction, 'short_part', v_short, 'long_part', s.reduction - v_short,
    'purchase_option', case when s.n = l.periods then l.purchase_option else 0 end,
    'short_account_no', (select account_no from erp.gl_accounts where id = l.short_account_id),
    'long_account_no', (select account_no from erp.gl_accounts where id = l.long_account_id),
    'interest_account_no', (select account_no from erp.gl_accounts where id = l.interest_account_id),
    'accrued_account_no', (select account_no from erp.gl_accounts where id = l.accrued_account_id));
end $$;

-- 7) Pago de la cuota siguiente de un préstamo: p = { loan_id, date? (por defecto, el vencimiento), bank_account_no? }
--    (el leasing no: su cuota lleva IVA y se registra como factura recibida de la entidad)
create or replace function erp.loan_payment(p jsonb)
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare l erp.loans; x jsonb; v_date date; a_bank uuid; v_entry uuid;
begin
  select * into l from erp.loans where id = (p->>'loan_id')::uuid;
  if not found then raise exception 'Loan not found'; end if;
  if l.status <> 'active' then raise exception 'The loan is not active (%)', l.status; end if;
  if l.kind = 'leasing' then raise exception 'A finance lease instalment has VAT: register the invoice of the leasing company'; end if;
  x := erp.loan_next_instalment(l.id);
  v_date := coalesce((p->>'date')::date, (x->>'due_date')::date);
  perform erp.loan_check(l.company_id, v_date);
  if v_date < (select max(event_date) from erp.loan_events where loan_id = l.id and status = 'posted') then
    raise exception 'The date is earlier than the last posting of this loan';
  end if;
  a_bank := case when nullif(btrim(p->>'bank_account_no'), '') is not null then erp.equity_bank(l.company_id, p->>'bank_account_no')
                 else coalesce(l.bank_account_id, erp.equity_bank(l.company_id, null)) end;
  v_entry := erp.equity_entry(l.company_id, v_date, 'Préstamo · cuota ' || (x->>'n') || '/' || l.periods || ' · ' || l.description, l.code,
               jsonb_build_array(erp.equity_line(l.accrued_account_id, (x->>'accrued_used')::numeric, 0),
                                 erp.equity_line(l.interest_account_id, (x->>'interest_expense')::numeric, 0),
                                 erp.equity_line(l.short_account_id, (x->>'short_part')::numeric, 0),
                                 erp.equity_line(l.long_account_id, (x->>'long_part')::numeric, 0),
                                 erp.equity_line(a_bank, 0, (x->>'payment')::numeric)));
  insert into erp.loan_events (loan_id, company_id, kind, event_date, n, amount, interest, accrued_used, short_part, long_part, entry_id)
  values (l.id, l.company_id, 'payment', v_date, (x->>'n')::int, (x->>'payment')::numeric, (x->>'interest_expense')::numeric,
          (x->>'accrued_used')::numeric, (x->>'short_part')::numeric, (x->>'long_part')::numeric, v_entry);
  if (x->>'n')::int = l.periods then update erp.loans set status = 'repaid' where id = l.id; end if;
  return x || jsonb_build_object('date', v_date, 'entry_no', (select entry_no from erp.journal_entries where id = v_entry));
end $$;

-- 8) Cierre del ejercicio: intereses devengados y reclasificación a corto de todos los préstamos vivos a una fecha
create or replace function erp.loan_year_end_preview(p_company uuid, p_date date)
returns jsonb language plpgsql stable security definer set search_path = erp, public as $$
declare r jsonb := '[]'; l erp.loans; a jsonb; pos jsonb;
begin
  if not erp.can_read(p_company) then raise exception 'No permission to read this company'; end if;
  for l in select * from erp.loans where company_id = p_company and status = 'active' and start_date <= p_date order by code loop
    a := erp.loan_accrual_amount(l.id, p_date); pos := erp.loan_position(l.id);
    r := r || jsonb_build_object('loan_id', l.id, 'code', l.code, 'kind', l.kind, 'description', l.description,
      'accrual', coalesce((a->>'amount')::numeric, 0), 'accrual_n', a->'n', 'fraction', a->'fraction', 'days', a->'days',
      'overdue', coalesce((a->>'overdue')::boolean, false), 'overdue_due_date', case when (a->>'overdue')::boolean then a->'due_date' end,
      'short_now', (pos->>'short')::numeric, 'short_target', erp.loan_short_target(l.id, p_date),
      'reclassification', erp.loan_short_target(l.id, p_date) - (pos->>'short')::numeric,
      'outstanding', (pos->>'short')::numeric + (pos->>'long')::numeric, 'accrued', (pos->>'accrued')::numeric);
  end loop;
  return jsonb_build_object('date', p_date, 'loans', r,
    'accrual_total', (select coalesce(sum((x->>'accrual')::numeric), 0) from jsonb_array_elements(r) x),
    'reclassification_total', (select coalesce(sum((x->>'reclassification')::numeric), 0) from jsonb_array_elements(r) x),
    'overdue', (select count(*) from jsonb_array_elements(r) x where (x->>'overdue')::boolean));
end $$;

create or replace function erp.loan_year_end(p_company uuid, p_date date)
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare pv jsonb; x jsonb; l erp.loans; v_entry uuid; v_amt numeric; v_posted int := 0;
begin
  perform erp.loan_check(p_company, p_date);
  pv := erp.loan_year_end_preview(p_company, p_date);
  for x in select * from jsonb_array_elements(pv->'loans') loop
    select * into l from erp.loans where id = (x->>'loan_id')::uuid;
    if (x->>'overdue')::boolean then
      raise exception 'Instalment of % due on % is not posted: post it first', l.code, x->>'overdue_due_date';
    end if;
    if exists (select 1 from erp.loan_events where loan_id = l.id and status = 'posted' and event_date > p_date) then
      raise exception '% has postings after %', l.code, p_date;
    end if;
    v_amt := (x->>'accrual')::numeric;
    if v_amt > 0 then
      v_entry := erp.equity_entry(p_company, p_date, 'Intereses devengados y no vencidos · ' || l.description, l.code,
                   jsonb_build_array(erp.equity_line(l.interest_account_id, v_amt, 0), erp.equity_line(l.accrued_account_id, 0, v_amt)));
      insert into erp.loan_events (loan_id, company_id, kind, event_date, n, amount, entry_id)
      values (l.id, p_company, 'accrual', p_date, (x->>'accrual_n')::int, v_amt, v_entry);
      v_posted := v_posted + 1;
    end if;
    v_amt := (x->>'reclassification')::numeric;
    if v_amt <> 0 then
      v_entry := erp.equity_entry(p_company, p_date, 'Reclasificación a corto plazo · ' || l.description, l.code,
                   case when v_amt > 0 then jsonb_build_array(erp.equity_line(l.long_account_id, v_amt, 0), erp.equity_line(l.short_account_id, 0, v_amt))
                        else jsonb_build_array(erp.equity_line(l.short_account_id, -v_amt, 0), erp.equity_line(l.long_account_id, 0, -v_amt)) end);
      insert into erp.loan_events (loan_id, company_id, kind, event_date, amount, entry_id)
      values (l.id, p_company, 'reclassification', p_date, v_amt, v_entry);
      v_posted := v_posted + 1;
    end if;
  end loop;
  return pv || jsonb_build_object('entries', v_posted);
end $$;

-- 9) Deshacer el último movimiento de un préstamo (si es el alta, el préstamo queda anulado)
create or replace function erp.loan_cancel(p_loan uuid)
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare l erp.loans; ev erp.loan_events;
begin
  select * into l from erp.loans where id = p_loan;
  if not found then raise exception 'Loan not found'; end if;
  if not erp.can_write(l.company_id) then raise exception 'No permission to change loans in this company'; end if;
  perform pg_advisory_xact_lock(hashtext('loans/' || l.company_id));
  select * into ev from erp.loan_events where loan_id = p_loan and status = 'posted' order by seq desc limit 1;
  if not found then raise exception 'The loan is already cancelled'; end if;
  if ev.invoice_id is not null then raise exception 'This instalment is an invoice: cancel the invoice'; end if;
  if exists (select 1 from erp.fiscal_years f where f.company_id = l.company_id and ev.event_date between f.starting_date and f.ending_date and f.status = 'closed') then
    raise exception 'The year of this posting is closed: reopen it first';
  end if;
  if ev.entry_id is not null then perform erp.adjust_reverse(ev.entry_id, ev.event_date, 'Deshacer ' || l.code); end if;
  update erp.loan_events set status = 'cancelled' where id = ev.id;
  update erp.loans set status = case when ev.kind = 'start' then 'cancelled' else 'active' end where id = l.id;
  return jsonb_build_object('code', l.code, 'kind', ev.kind, 'n', ev.n, 'date', ev.event_date);
end $$;

-- 10) Estado de los préstamos a una fecha (lo que enseña la pantalla)
create or replace function erp.loan_status(p_company uuid)
returns jsonb language plpgsql stable security definer set search_path = erp, public as $$
begin
  if not erp.can_read(p_company) then raise exception 'No permission to read this company'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('loan_id', l.id, 'code', l.code, 'kind', l.kind, 'description', l.description,
      'lender', l.lender, 'status', l.status, 'start_date', l.start_date, 'periods', l.periods, 'frequency', l.frequency,
      'instalment', l.instalment, 'net_amount', l.net_amount, 'effective_rate_year', l.effective_rate_year,
      'paid', (pos->>'paid')::int, 'short', (pos->>'short')::numeric, 'long', (pos->>'long')::numeric, 'accrued', (pos->>'accrued')::numeric,
      'next', erp.loan_next_instalment(l.id)) order by l.code)
    from erp.loans l cross join lateral (select erp.loan_position(l.id) pos) z
    where l.company_id = p_company and l.status <> 'cancelled'), '[]');
end $$;

revoke execute on function erp.loan_account(uuid, text, text, text, text), erp.loan_check(uuid, date), erp.loan_position(uuid),
  erp.loan_short_target(uuid, date), erp.loan_accrual_amount(uuid, date) from anon, public, authenticated;
revoke execute on function erp.loan_calc(jsonb), erp.loan_create(jsonb), erp.loan_next_instalment(uuid), erp.loan_payment(jsonb),
  erp.loan_year_end_preview(uuid, date), erp.loan_year_end(uuid, date), erp.loan_cancel(uuid), erp.loan_status(uuid),
  erp.loan_days360(date, date), erp.loan_french_payments(numeric, numeric, int), erp.loan_present_value(numeric[], numeric),
  erp.loan_effective_rate(numeric[], numeric), erp.loan_rows(numeric[], numeric, numeric) from anon, public;
grant execute on function erp.loan_calc(jsonb), erp.loan_create(jsonb), erp.loan_next_instalment(uuid), erp.loan_payment(jsonb),
  erp.loan_year_end_preview(uuid, date), erp.loan_year_end(uuid, date), erp.loan_cancel(uuid), erp.loan_status(uuid),
  erp.loan_days360(date, date), erp.loan_french_payments(numeric, numeric, int), erp.loan_present_value(numeric[], numeric),
  erp.loan_effective_rate(numeric[], numeric), erp.loan_rows(numeric[], numeric, numeric) to authenticated;

-- 11) Módulo propio: no se anula desde el diario, no es un asiento manual, tiene su origen en el diario y en el
--     auditor, y se borra con la empresa (versiones de la 0060; cambia solo lo marcado «v0.43.0»)
CREATE OR REPLACE FUNCTION erp.tg_entry_adjust_reverse()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.reversal_of is not null and coalesce(current_setting('erp.adjust_engine', true), '') <> 'on' then
    if exists (select 1 from erp.accruals where new.reversal_of in (entry_id, reversal_entry_id)) then
      raise exception 'This entry belongs to an accrual: undo it from Year-end adjustments';
    end if;
    if exists (select 1 from erp.receivable_impairments where new.reversal_of in (entry_id, end_entry_id))
       or exists (select 1 from erp.receivable_writeoffs where entry_id = new.reversal_of) then
      raise exception 'This entry belongs to a receivable impairment: undo it from Year-end adjustments';
    end if;
    -- v0.37.0: provisiones
    if exists (select 1 from erp.provision_movements where entry_id = new.reversal_of) then
      raise exception 'This entry belongs to a provision: undo it from Year-end adjustments';
    end if;
    -- v0.37.0: inventario del cierre
    if exists (select 1 from erp.inventory_counts where entry_id = new.reversal_of) then
      raise exception 'This entry belongs to an inventory count: undo it from Year-end adjustments';
    end if;
    -- v0.41.0: Impuesto sobre Sociedades
    if exists (select 1 from erp.corporate_tax_returns where new.reversal_of in (current_entry_id, deferred_entry_id)) then
      raise exception 'This entry belongs to the corporate income tax: undo it from Corporate tax';
    end if;
    -- v0.42.0: operaciones societarias
    if exists (select 1 from erp.equity_operations where new.reversal_of = any (entry_ids)) then
      raise exception 'This entry belongs to an equity operation: undo it from Equity operations';
    end if;
    -- v0.43.0: préstamos y arrendamiento financiero
    if exists (select 1 from erp.loan_events where entry_id = new.reversal_of) then
      raise exception 'This entry belongs to a loan or finance lease: undo it from Financing';
    end if;
    -- v0.38.0: nóminas y sus pagos
    if exists (select 1 from erp.payroll_runs where new.reversal_of in (entry_id, net_payment_entry_id, ss_payment_entry_id)) then
      raise exception 'This entry belongs to a payroll: undo it from Payroll';
    end if;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION erp.entry_is_manual(p_entry uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select e.entry_type = 'normal' and e.reversal_of is null and e.reversed_by is null and e.import_batch_id is null
     and not exists (select 1 from erp.invoices i where i.entry_id = e.id)
     and not exists (select 1 from erp.tax_settlements s where s.entry_id = e.id)
     and not exists (select 1 from erp.pro_rata p where p.entry_id = e.id)
     and not exists (select 1 from erp.year_closings c where e.id in (c.closing_pl_entry_id, c.closing_entry_id, c.opening_entry_id))
     and not exists (select 1 from erp.payments py where py.entry_id = e.id and not py.linked)
     and not exists (select 1 from erp.asset_depreciations d where d.entry_id = e.id)
     and not exists (select 1 from erp.fixed_assets fa where fa.disposal_entry_id = e.id)
     and not exists (select 1 from erp.asset_events ae where ae.entry_id = e.id)   -- v0.37.0
     -- v0.36.0: periodificaciones y deterioros
     and not exists (select 1 from erp.accruals ac where e.id in (ac.entry_id, ac.reversal_entry_id))
     and not exists (select 1 from erp.receivable_impairments ri where e.id in (ri.entry_id, ri.end_entry_id))
     -- v0.37.0: provisiones
     and not exists (select 1 from erp.provision_movements pm where pm.entry_id = e.id)
     and not exists (select 1 from erp.inventory_counts ic where ic.entry_id = e.id)   -- v0.37.0: inventario
     and not exists (select 1 from erp.payroll_runs pr where e.id in (pr.entry_id, pr.net_payment_entry_id, pr.ss_payment_entry_id))   -- v0.38.0
     and not exists (select 1 from erp.corporate_tax_returns ct where e.id in (ct.current_entry_id, ct.deferred_entry_id))   -- v0.41.0
     and not exists (select 1 from erp.equity_operations eo where e.id = any (eo.entry_ids))   -- v0.42.0
     and not exists (select 1 from erp.loan_events le where le.entry_id = e.id)   -- v0.43.0
  from erp.journal_entries e where e.id = p_entry;
$function$
;

create or replace view erp.v_general_journal with (security_invoker = true) as
select e.company_id,
       fy.year          as fiscal_year,
       e.entry_no,
       e.posting_date,
       e.description    as entry_description,
       e.document_no,
       e.entry_type,
       l.line_no,
       a.account_no,
       a.name           as account_name,
       a.name_en        as account_name_en,
       l.debit,
       l.credit,
       coalesce(l.description, e.description) as description,
       e.id             as entry_id,
       ro.entry_no      as reversal_of_no,
       rb.entry_no      as reversed_by_no,
       case when exists (select 1 from erp.invoices i where i.entry_id = e.id) then 'invoice'
            when exists (select 1 from erp.tax_settlements s where s.entry_id = e.id or s.entry_id = e.reversal_of) then 'settlement'
            when exists (select 1 from erp.year_closings c
                         where coalesce(e.reversal_of, e.id) in (c.closing_pl_entry_id, c.closing_entry_id, c.opening_entry_id)) then 'closing'
            -- v0.36.0: periodificaciones y deterioros (la insolvencia firme también es un «cobro»: va antes)
            when exists (select 1 from erp.accruals ac where coalesce(e.reversal_of, e.id) in (ac.entry_id, ac.reversal_entry_id)) then 'accrual'
            when exists (select 1 from erp.receivable_impairments ri where coalesce(e.reversal_of, e.id) in (ri.entry_id, ri.end_entry_id))
              or exists (select 1 from erp.receivable_writeoffs w where w.entry_id = coalesce(e.reversal_of, e.id)) then 'impairment'
            -- v0.37.0: provisiones
            when exists (select 1 from erp.provision_movements pm where pm.entry_id = coalesce(e.reversal_of, e.id)) then 'provision'
            when exists (select 1 from erp.inventory_counts ic where ic.entry_id = coalesce(e.reversal_of, e.id)) then 'inventory'
            -- v0.41.0: Impuesto sobre Sociedades
            when exists (select 1 from erp.corporate_tax_returns ct
                         where coalesce(e.reversal_of, e.id) in (ct.current_entry_id, ct.deferred_entry_id)) then 'corporate_tax'
            -- v0.42.0: operaciones societarias
            when exists (select 1 from erp.equity_operations eo where coalesce(e.reversal_of, e.id) = any (eo.entry_ids)) then 'equity'
            -- v0.43.0: préstamos y arrendamiento financiero
            when exists (select 1 from erp.loan_events le where le.entry_id = coalesce(e.reversal_of, e.id)) then 'financing'
            -- v0.38.0: nóminas y sus pagos
            when exists (select 1 from erp.payroll_runs pr
                         where coalesce(e.reversal_of, e.id) in (pr.entry_id, pr.net_payment_entry_id, pr.ss_payment_entry_id)) then 'payroll'
            when exists (select 1 from erp.payments py where not py.linked and (py.entry_id = e.id or py.cancel_entry_id = e.id)) then 'payment'
            when exists (select 1 from erp.asset_depreciations d where d.entry_id = coalesce(e.reversal_of, e.id))
              or exists (select 1 from erp.fixed_assets fa where fa.disposal_entry_id = coalesce(e.reversal_of, e.id))
              or exists (select 1 from erp.asset_events ae where ae.entry_id = coalesce(e.reversal_of, e.id)) then 'asset'
            when e.reversal_of is not null then 'reversal'
            else 'manual' end as source,
       e.reversal_reason
from erp.journal_entries e
join erp.fiscal_years  fy on fy.id = e.fiscal_year_id
join erp.journal_lines l  on l.entry_id = e.id
join erp.gl_accounts   a  on a.id = l.gl_account_id
left join erp.journal_entries ro on ro.id = e.reversal_of
left join erp.journal_entries rb on rb.id = e.reversed_by
where e.status = 'posted';

CREATE OR REPLACE FUNCTION erp.audit_lines(p_company uuid, p_year integer, p_to_date date DEFAULT NULL::date)
 RETURNS TABLE(entry_id uuid, entry_no integer, posting_date date, k uuid, source text, account_no text, account_name text, debit numeric, credit numeric, tax_code text)
 LANGUAGE sql
 STABLE
AS $function$
  select e.id, e.entry_no, e.posting_date, coalesce(e.reversal_of, e.id),
         case when exists (select 1 from erp.invoices i where i.entry_id = coalesce(e.reversal_of, e.id)) then 'invoice'
              when exists (select 1 from erp.tax_settlements s where s.entry_id = coalesce(e.reversal_of, e.id)) then 'settlement'
              when exists (select 1 from erp.pro_rata p where p.entry_id = coalesce(e.reversal_of, e.id)) then 'pro_rata'
              -- v0.36.0: periodificaciones y deterioros (antes que los cobros: la insolvencia firme también lo es)
              when exists (select 1 from erp.accruals ac where coalesce(e.reversal_of, e.id) in (ac.entry_id, ac.reversal_entry_id)) then 'accrual'
              when exists (select 1 from erp.receivable_impairments ri where coalesce(e.reversal_of, e.id) in (ri.entry_id, ri.end_entry_id))
                or exists (select 1 from erp.receivable_writeoffs w where w.entry_id = coalesce(e.reversal_of, e.id)) then 'impairment'
              -- v0.37.0: provisiones
              when exists (select 1 from erp.provision_movements pm where pm.entry_id = coalesce(e.reversal_of, e.id)) then 'provision'
              when exists (select 1 from erp.inventory_counts ic where ic.entry_id = coalesce(e.reversal_of, e.id)) then 'inventory'
              -- v0.41.0: Impuesto sobre Sociedades
              when exists (select 1 from erp.corporate_tax_returns ct
                           where coalesce(e.reversal_of, e.id) in (ct.current_entry_id, ct.deferred_entry_id)) then 'corporate_tax'
              -- v0.42.0: operaciones societarias
              when exists (select 1 from erp.equity_operations eo where coalesce(e.reversal_of, e.id) = any (eo.entry_ids)) then 'equity'
              -- v0.43.0: préstamos y arrendamiento financiero
              when exists (select 1 from erp.loan_events le where le.entry_id = coalesce(e.reversal_of, e.id)) then 'financing'
              -- v0.38.0: nóminas y sus pagos
              when exists (select 1 from erp.payroll_runs pr
                           where coalesce(e.reversal_of, e.id) in (pr.entry_id, pr.net_payment_entry_id, pr.ss_payment_entry_id)) then 'payroll'
              when exists (select 1 from erp.payments py where not py.linked
                           and coalesce(e.reversal_of, e.id) in (py.entry_id, py.cancel_entry_id)) then 'payment'
              when exists (select 1 from erp.asset_depreciations d where d.entry_id = coalesce(e.reversal_of, e.id))
                or exists (select 1 from erp.fixed_assets fa where fa.disposal_entry_id = coalesce(e.reversal_of, e.id))
                or exists (select 1 from erp.asset_events ae where ae.entry_id = coalesce(e.reversal_of, e.id)) then 'asset'
              when o.import_batch_id is not null then 'import'
              else 'manual' end,
         g.account_no, g.name, l.debit, l.credit, l.tax_code
  from erp.journal_entries e
  join erp.fiscal_years fy on fy.id = e.fiscal_year_id
  join erp.journal_entries o on o.id = coalesce(e.reversal_of, e.id)
  join erp.journal_lines l on l.entry_id = e.id
  join erp.gl_accounts g on g.id = l.gl_account_id
  where e.company_id = p_company and fy.year = p_year and e.status = 'posted' and e.entry_type = 'normal'
    and (p_to_date is null or e.posting_date <= p_to_date);
$function$
;

CREATE OR REPLACE FUNCTION erp.delete_company_step(p_company uuid, p_batch integer DEFAULT 5000)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare
  v_ids  uuid[];
  v_left int;
begin
  if not exists (select 1 from erp.company_users
                 where company_id = p_company and user_id = auth.uid() and role = 'admin') then
    raise exception 'Only the company admin can delete it';
  end if;
  perform set_config('erp.deleting_company', 'on', true);   -- solo dura esta transacción

  -- Documentos que apuntan a asientos (en la primera tanda; en las siguientes ya no hay nada)
  delete from erp.loans                  where company_id = p_company;   -- v0.43.0 (su cuadro y sus movimientos, en cascada)
  delete from erp.equity_operations      where company_id = p_company;   -- v0.42.0
  delete from erp.corporate_tax_returns  where company_id = p_company;   -- v0.41.0 (sus ajustes, en cascada)
  delete from erp.payroll_runs           where company_id = p_company;   -- v0.38.0 (las nóminas de cada empleado, en cascada)
  delete from erp.employees              where company_id = p_company;   -- v0.38.0
  delete from erp.inventory_counts       where company_id = p_company;   -- v0.37.0 (sus líneas, en cascada)
  delete from erp.provision_movements    where company_id = p_company;   -- v0.37.0
  delete from erp.provisions             where company_id = p_company;   -- v0.37.0
  delete from erp.receivable_writeoffs   where company_id = p_company;   -- v0.36.0 (antes que los pagos)
  delete from erp.receivable_impairments where company_id = p_company;   -- v0.36.0
  delete from erp.accruals               where company_id = p_company;   -- v0.36.0
  delete from erp.asset_depreciations where company_id = p_company;
  delete from erp.fixed_assets    where company_id = p_company;
  delete from erp.payments        where company_id = p_company;   -- sus aplicaciones, en cascada
  delete from erp.year_closings   where company_id = p_company;
  delete from erp.pro_rata        where company_id = p_company;
  delete from erp.tax_settlements where company_id = p_company;
  delete from erp.invoices        where company_id = p_company;   -- sus líneas, en cascada

  -- Tanda de asientos (los más recientes primero) + su pareja de anulación
  with b as (
    select id, reversal_of, reversed_by from erp.journal_entries
    where company_id = p_company
    order by posting_date desc, entry_no desc nulls first
    limit greatest(p_batch, 1)
  )
  select array_agg(distinct x) into v_ids
  from (select id from b
        union all select reversal_of from b where reversal_of is not null
        union all select reversed_by from b where reversed_by is not null) s(x);

  if v_ids is not null then
    delete from erp.journal_lines   where entry_id = any (v_ids);
    delete from erp.journal_entries where id = any (v_ids);
  end if;

  select count(*)::int into v_left from erp.journal_entries where company_id = p_company;
  if v_left = 0 then
    delete from erp.import_lines where company_id = p_company;
    delete from erp.companies    where id = p_company;
  end if;

  perform set_config('erp.deleting_company', 'off', true);
  return v_left;
end $function$
;
