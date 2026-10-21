-- =====================================================================
-- 0060 · OPERACIONES SOCIETARIAS (I): capital, reparto del resultado, dividendos y pérdidas · v0.42.0
-- ---------------------------------------------------------------------
-- Las operaciones del patrimonio neto de una sociedad de capital (LSC = RDLeg 1/2010, con la Ley 18/2022), cada una
-- con sus asientos del PGC y las comprobaciones de la ley ANTES de contabilizar:
--   · Constitución (art. 4, 78 y 79 LSC): 190 / 194 → 572 + 1030 → 100. SA: capital ≥ 60.000 y al menos el 25 %
--     desembolsado; SL: capital ≥ 1 € y todo desembolsado.
--   · Ampliación de capital, con prima (110) o con cargo a reservas (art. 295 a 304).
--   · Dividendos pasivos: exigir lo no desembolsado (1030 → 5580) y cobrarlo.
--   · Reparto del resultado (art. 273 y 274; SL de menos de 3.000 €: art. 4.2): 129 → 121 / 112 / 557 / 526 / 113.
--       reserva legal: 10 % del beneficio hasta el 20 % del capital (SL de menos de 3.000 €: 20 % hasta que capital +
--       reserva legal sumen 3.000) · las pérdidas pendientes se compensan primero · dividendo solo si el patrimonio
--       neto no queda por debajo del capital.
--   · Dividendo a cuenta (art. 277): límite = resultado desde el cierre − pérdidas anteriores − impuesto estimado −
--       reserva legal, y tesorería suficiente.
--   · Pago del dividendo con la retención del 19 % (art. 101.4 LIRPF, 90 RIRPF): 526 → 47512 (modelo 123) + 572.
--   · Compensar pérdidas con reservas (113 → 121) y reducir el capital por pérdidas (art. 320 y 322).
-- Cada operación es un módulo propio (no se anula desde el diario: se deshace desde su pantalla, de la última a la
-- primera). La forma jurídica (SA / SL) va en la ficha de la empresa.
-- PENDIENTE DE VALIDAR POR DIOSVELY: la reserva legal sobre el beneficio del ejercicio aunque haya pérdidas anteriores.
-- Re-ejecutable.
-- =====================================================================

-- 1) Forma jurídica de la empresa
alter table erp.companies add column if not exists legal_form text not null default 'sl';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'companies_legal_form_check') then
    alter table erp.companies add constraint companies_legal_form_check check (legal_form in ('sa', 'sl'));
  end if;
end $$;
comment on column erp.companies.legal_form is 'sa: sociedad anónima · sl: sociedad de responsabilidad limitada (LSC). Decide la reserva legal y los desembolsos pendientes.';

-- 1b) Subgrupo 19 del PGC «Situaciones transitorias de financiación» (la emisión y la suscripción del capital): se
--     añade a la plantilla y, como cuentas de título, a las empresas que ya existen
insert into erp.coa_template (account_no, name, name_en, account_category) values
('19', 'Situaciones transitorias de financiación', 'Transitional financing situations', 'mixed'),
('190', 'Acciones o participaciones emitidas', 'Shares issued', 'mixed'),
('192', 'Suscriptores de acciones', 'Share subscribers', 'mixed'),
('194', 'Capital emitido pendiente de inscripción', 'Capital issued pending registration', 'mixed'),
('195', 'Acciones o participaciones emitidas consideradas como pasivos financieros', 'Shares issued classified as financial liabilities', 'mixed'),
('197', 'Suscriptores de acciones consideradas como pasivos financieros', 'Subscribers of shares classified as financial liabilities', 'mixed'),
('199', 'Acciones o participaciones emitidas consideradas como pasivos financieros pendientes de inscripción', 'Shares classified as financial liabilities pending registration', 'mixed')
on conflict (account_no) do nothing;
insert into erp.gl_accounts (company_id, account_no, name, name_en, account_type, template_account, account_category)
select c.id, t.account_no, t.name, t.name_en, 'heading', t.account_no, t.account_category
from erp.companies c cross join erp.coa_template t
where t.account_no ~ '^19'
  and not exists (select 1 from erp.gl_accounts g where g.company_id = c.id and g.account_no = t.account_no);

-- 2) Las operaciones
create table if not exists erp.equity_operations (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references erp.companies(id) on delete cascade,
  code        text not null,
  kind        text not null check (kind in ('incorporation', 'capital_increase', 'reserves_to_capital', 'call', 'distribution',
                                            'interim_dividend', 'dividend_payment', 'loss_offset', 'capital_reduction')),
  op_date     date not null,
  description text not null,
  data        jsonb not null default '{}',     -- lo que se pidió
  result      jsonb not null default '{}',     -- lo que se calculó (reserva legal, límites…)
  entry_ids   uuid[] not null default '{}',
  status      text not null default 'posted' check (status in ('posted', 'cancelled')),
  created_at  timestamptz not null default now(),
  unique (company_id, code)
);
comment on table erp.equity_operations is 'Equity operations of a company (LSC): incorporation, capital increases, calls, distribution of the result, dividends and losses.';
create index if not exists equity_operations_company_idx on erp.equity_operations (company_id, op_date);
create index if not exists equity_operations_entries_idx on erp.equity_operations using gin (entry_ids);
alter table erp.equity_operations enable row level security;
drop policy if exists read on erp.equity_operations;
create policy read on erp.equity_operations for select to authenticated using (erp.can_read(company_id));
revoke all on erp.equity_operations from anon, public;
grant select on erp.equity_operations to authenticated;   -- se escriben con las funciones

-- 3) Ayudas
-- Saldo acreedor (Haber − Debe) de las cuentas que empiezan por un prefijo, en el ejercicio de la fecha y hasta ella
-- (con la apertura; sin la regularización ni el cierre: la 129 de un año se reparte en el siguiente)
create or replace function erp.equity_bal(p_company uuid, p_prefix text, p_date date)
returns numeric language sql stable security definer set search_path = erp, public as $$
  select coalesce(sum(l.credit - l.debit), 0)
  from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id join erp.gl_accounts g on g.id = l.gl_account_id
  join erp.fiscal_years f on f.id = e.fiscal_year_id
  where e.company_id = p_company and e.status = 'posted' and e.entry_type not in ('closing', 'closing_pl')
    and p_date between f.starting_date and f.ending_date and e.posting_date <= p_date and g.account_no like p_prefix || '%';
$$;

-- Patrimonio neto a una fecha: grupos 10 a 13, el dividendo a cuenta (resta) y, si se pide, el resultado del ejercicio
-- en curso (los grupos 6 y 7 aún sin regularizar). El reparto (art. 273 LSC) mira el del balance aprobado: sin él.
create or replace function erp.equity_net_worth(p_company uuid, p_date date, p_with_current boolean default true)
returns numeric language sql stable as $$
  select erp.equity_bal(p_company, '10', p_date) + erp.equity_bal(p_company, '11', p_date) + erp.equity_bal(p_company, '12', p_date)
       + erp.equity_bal(p_company, '13', p_date) + erp.equity_bal(p_company, '557', p_date)
       + case when p_with_current then erp.equity_bal(p_company, '6', p_date) + erp.equity_bal(p_company, '7', p_date) else 0 end;
$$;

-- Reserva legal que toca con un beneficio (art. 274 LSC; SL de menos de 3.000 €: art. 4.2 LSC)
create or replace function erp.equity_legal_reserve(p_form text, p_capital numeric, p_reserve numeric, p_profit numeric)
returns numeric language sql immutable as $$
  select case when p_profit <= 0 then 0
              when p_form = 'sl' and p_capital < 3000
                then greatest(0, least(round(p_profit * 0.20, 2), 3000 - p_capital - p_reserve))
              else greatest(0, least(round(p_profit * 0.10, 2), round(p_capital * 0.20, 2) - p_reserve)) end;
$$;

-- Subcuenta de tesorería: la pedida (tiene que ser del 57) o la primera del 572 (si no hay, se crea)
create or replace function erp.equity_bank(p_company uuid, p_no text)
returns uuid language plpgsql security definer set search_path = erp, public as $$
declare v uuid;
begin
  if nullif(btrim(p_no), '') is not null then
    select id into v from erp.gl_accounts where company_id = p_company and account_no = btrim(p_no) and account_type = 'posting' and account_no like '57%';
    if v is null then raise exception 'Bank account % does not exist (it must be a 57 subaccount)', p_no; end if;
    return v;
  end if;
  select id into v from erp.gl_accounts where company_id = p_company and account_type = 'posting' and account_no like '572%' order by account_no limit 1;
  return coalesce(v, erp.adjust_account(p_company, '572', 'Bancos e instituciones de crédito c/c vista, euros'));
end $$;

-- Un asiento de la operación: p_lines = [{ account_id, debit, credit }] (las de importe cero no se graban)
create or replace function erp.equity_entry(p_company uuid, p_date date, p_desc text, p_doc text, p_lines jsonb)
returns uuid language plpgsql security definer set search_path = erp, public as $$
declare v_entry uuid;
begin
  if not exists (select 1 from jsonb_array_elements(p_lines) l where coalesce((l->>'debit')::numeric, 0) + coalesce((l->>'credit')::numeric, 0) > 0) then
    return null;
  end if;
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no)
  values (p_company, erp.adjust_fiscal_year(p_company, p_date), p_date, left(p_desc, 250), p_doc)
  returning id into v_entry;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit)
  select v_entry, p_company, row_number() over (), (l->>'account_id')::uuid, coalesce((l->>'debit')::numeric, 0), coalesce((l->>'credit')::numeric, 0)
  from jsonb_array_elements(p_lines) l where coalesce((l->>'debit')::numeric, 0) + coalesce((l->>'credit')::numeric, 0) > 0;
  perform erp.adjust_finish(v_entry);
  return v_entry;
end $$;

create or replace function erp.equity_line(p_account uuid, p_debit numeric, p_credit numeric)
returns jsonb language sql immutable as $$
  select jsonb_build_object('account_id', p_account, 'debit', round(coalesce(p_debit, 0), 2), 'credit', round(coalesce(p_credit, 0), 2));
$$;

-- Comprobaciones comunes y número de la operación (SOC-0001…)
create or replace function erp.equity_start(p_company uuid, p_date date)
returns text language plpgsql security definer set search_path = erp, public as $$
declare v_fy erp.fiscal_years; v_code text;
begin
  if not erp.can_write(p_company) then raise exception 'No permission to post equity operations in this company'; end if;
  if p_date is null then raise exception 'The date is required'; end if;
  select * into v_fy from erp.fiscal_years where company_id = p_company and p_date between starting_date and ending_date;
  if not found then raise exception 'No fiscal year for date %: create it first', p_date; end if;
  if v_fy.status = 'closed' then raise exception 'Fiscal year % is closed', v_fy.year; end if;
  perform pg_advisory_xact_lock(hashtext('equity/' || p_company));
  select 'SOC-' || lpad((count(*) + 1)::text, 4, '0') into v_code from erp.equity_operations where company_id = p_company;
  return v_code;
end $$;

create or replace function erp.equity_save(p_company uuid, p_code text, p_kind text, p_date date, p_desc text, p_data jsonb, p_result jsonb, p_entries uuid[])
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare v_id uuid;
begin
  insert into erp.equity_operations (company_id, code, kind, op_date, description, data, result, entry_ids)
  values (p_company, p_code, p_kind, p_date, p_desc, p_data, p_result, array_remove(p_entries, null))
  returning id into v_id;
  return p_result || jsonb_build_object('operation_id', v_id, 'code', p_code,
    'entry_nos', (select coalesce(jsonb_agg(e.entry_no order by e.entry_no), '[]') from erp.journal_entries e where e.id = any (p_entries)));
end $$;

-- 4) Estado del patrimonio neto a una fecha (lo que enseña la pantalla)
create or replace function erp.equity_status(p_company uuid, p_date date)
returns jsonb language plpgsql stable security definer set search_path = erp, public as $$
declare v_form text; v_cap numeric;
begin
  if not erp.can_read(p_company) then raise exception 'No permission to read this company'; end if;
  select legal_form into v_form from erp.companies where id = p_company;
  v_cap := erp.equity_bal(p_company, '100', p_date);
  return jsonb_build_object(
    'legal_form', v_form, 'date', p_date,
    'capital', v_cap,
    'uncalled', -erp.equity_bal(p_company, '1030', p_date),
    'called_unpaid', -erp.equity_bal(p_company, '5580', p_date),
    'premium', erp.equity_bal(p_company, '110', p_date),
    'legal_reserve', erp.equity_bal(p_company, '112', p_date),
    'voluntary_reserves', erp.equity_bal(p_company, '113', p_date),
    'prior_losses', -erp.equity_bal(p_company, '121', p_date),
    'result_to_distribute', erp.equity_bal(p_company, '129', p_date),
    'interim_dividend', -erp.equity_bal(p_company, '557', p_date),
    'dividend_payable', erp.equity_bal(p_company, '526', p_date),
    'net_worth', erp.equity_net_worth(p_company, p_date),
    'legal_reserve_cap', case when v_form = 'sl' and v_cap < 3000 then greatest(0, 3000 - v_cap) else round(v_cap * 0.20, 2) end,
    'low_capital_sl', v_form = 'sl' and v_cap < 3000,
    'cash', -erp.equity_bal(p_company, '57', p_date));
end $$;

-- 5) Constitución: p = { company_id, date, capital, paid_pct (SA: 25-100; SL: 100), bank_account_no? }
create or replace function erp.equity_incorporation(p jsonb)
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare
  v_company uuid := (p->>'company_id')::uuid; v_date date := (p->>'date')::date;
  v_cap numeric := round(coalesce((p->>'capital')::numeric, 0), 2); v_pct numeric := coalesce((p->>'paid_pct')::numeric, 100);
  v_form text; v_code text; v_paid numeric; a_190 uuid; a_194 uuid; a_1030 uuid; a_100 uuid; v_bank uuid; e1 uuid; e2 uuid; e3 uuid;
begin
  v_code := erp.equity_start(v_company, v_date);
  select legal_form into v_form from erp.companies where id = v_company;
  if exists (select 1 from erp.equity_operations where company_id = v_company and status = 'posted' and kind = 'incorporation')
     or erp.equity_bal(v_company, '100', v_date) <> 0 then
    raise exception 'The company already has share capital: use a capital increase';
  end if;
  if v_form = 'sa' and v_cap < 60000 then raise exception 'The share capital of an SA must be at least 60,000 (art. 4.3 LSC)'; end if;
  if v_cap < 1 then raise exception 'The share capital must be at least 1 euro (art. 4.1 LSC)'; end if;
  if v_form = 'sl' and v_pct <> 100 then raise exception 'In an SL the capital must be fully paid at incorporation (art. 78 LSC)'; end if;
  if v_pct < 25 or v_pct > 100 then raise exception 'At least 25 %% of the capital must be paid at incorporation (art. 79 LSC)'; end if;
  v_paid := round(v_cap * v_pct / 100, 2);
  a_190 := erp.adjust_account(v_company, '190', 'Acciones o participaciones emitidas');
  a_194 := erp.adjust_account(v_company, '194', 'Capital emitido pendiente de inscripción');
  a_100 := erp.adjust_account(v_company, '100', 'Capital social');
  v_bank := erp.equity_bank(v_company, p->>'bank_account_no');
  e1 := erp.equity_entry(v_company, v_date, 'Constitución · emisión del capital', v_code,
          jsonb_build_array(erp.equity_line(a_190, v_cap, 0), erp.equity_line(a_194, 0, v_cap)));
  if v_paid < v_cap then a_1030 := erp.adjust_account(v_company, '1030', 'Socios por desembolsos no exigidos, capital social'); end if;
  e2 := erp.equity_entry(v_company, v_date, 'Constitución · suscripción y desembolso', v_code,
          jsonb_build_array(erp.equity_line(v_bank, v_paid, 0), erp.equity_line(a_1030, v_cap - v_paid, 0), erp.equity_line(a_190, 0, v_cap)));
  e3 := erp.equity_entry(v_company, v_date, 'Constitución · inscripción en el Registro Mercantil', v_code,
          jsonb_build_array(erp.equity_line(a_194, v_cap, 0), erp.equity_line(a_100, 0, v_cap)));
  return erp.equity_save(v_company, v_code, 'incorporation', v_date, 'Constitución', p,
    jsonb_build_object('capital', v_cap, 'paid', v_paid, 'uncalled', v_cap - v_paid), array[e1, e2, e3]);
end $$;

-- 6) Ampliación de capital: p = { company_id, date, nominal, premium?, paid_pct? (SA: 25-100 del nominal; la prima,
--    entera), bank_account_no? }
create or replace function erp.equity_capital_increase(p jsonb)
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare
  v_company uuid := (p->>'company_id')::uuid; v_date date := (p->>'date')::date;
  v_nom numeric := round(coalesce((p->>'nominal')::numeric, 0), 2); v_prem numeric := round(coalesce((p->>'premium')::numeric, 0), 2);
  v_pct numeric := coalesce((p->>'paid_pct')::numeric, 100);
  v_form text; v_code text; v_paid numeric; a_190 uuid; a_194 uuid; a_1030 uuid; a_100 uuid; a_110 uuid; v_bank uuid; e1 uuid; e2 uuid; e3 uuid;
begin
  v_code := erp.equity_start(v_company, v_date);
  select legal_form into v_form from erp.companies where id = v_company;
  if erp.equity_bal(v_company, '100', v_date) <= 0 then raise exception 'There is no share capital yet: register the incorporation first'; end if;
  if v_nom <= 0 or v_prem < 0 then raise exception 'Invalid amounts for the capital increase'; end if;
  if v_form = 'sl' and v_pct <> 100 then raise exception 'In an SL the new capital must be fully paid (art. 78 LSC)'; end if;
  if v_pct < 25 or v_pct > 100 then raise exception 'At least 25 %% of the nominal value must be paid (art. 79 LSC)'; end if;
  v_paid := round(v_nom * v_pct / 100, 2) + v_prem;   -- la prima se desembolsa entera
  a_190 := erp.adjust_account(v_company, '190', 'Acciones o participaciones emitidas');
  a_194 := erp.adjust_account(v_company, '194', 'Capital emitido pendiente de inscripción');
  a_100 := erp.adjust_account(v_company, '100', 'Capital social');
  if v_prem > 0 then a_110 := erp.adjust_account(v_company, '110', 'Prima de emisión o asunción'); end if;
  v_bank := erp.equity_bank(v_company, p->>'bank_account_no');
  e1 := erp.equity_entry(v_company, v_date, 'Ampliación de capital · emisión', v_code,
          jsonb_build_array(erp.equity_line(a_190, v_nom + v_prem, 0), erp.equity_line(a_194, 0, v_nom), erp.equity_line(a_110, 0, v_prem)));
  if v_paid < v_nom + v_prem then a_1030 := erp.adjust_account(v_company, '1030', 'Socios por desembolsos no exigidos, capital social'); end if;
  e2 := erp.equity_entry(v_company, v_date, 'Ampliación de capital · suscripción y desembolso', v_code,
          jsonb_build_array(erp.equity_line(v_bank, v_paid, 0), erp.equity_line(a_1030, v_nom + v_prem - v_paid, 0), erp.equity_line(a_190, 0, v_nom + v_prem)));
  e3 := erp.equity_entry(v_company, v_date, 'Ampliación de capital · inscripción en el Registro Mercantil', v_code,
          jsonb_build_array(erp.equity_line(a_194, v_nom, 0), erp.equity_line(a_100, 0, v_nom)));
  return erp.equity_save(v_company, v_code, 'capital_increase', v_date, 'Ampliación de capital', p,
    jsonb_build_object('nominal', v_nom, 'premium', v_prem, 'paid', v_paid, 'uncalled', v_nom + v_prem - v_paid), array[e1, e2, e3]);
end $$;

-- 7) Ampliación con cargo a reservas (art. 303 LSC): p = { company_id, date, amount, source: '113' (voluntarias) | '110' (prima) }
create or replace function erp.equity_reserves_to_capital(p jsonb)
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare
  v_company uuid := (p->>'company_id')::uuid; v_date date := (p->>'date')::date;
  v_amt numeric := round(coalesce((p->>'amount')::numeric, 0), 2); v_src text := coalesce(p->>'source', '113'); v_code text; v_acc uuid; e1 uuid;
begin
  v_code := erp.equity_start(v_company, v_date);
  if v_src not in ('113', '110') then raise exception 'Invalid source: 113 (voluntary reserves) or 110 (share premium)'; end if;
  if erp.equity_bal(v_company, '100', v_date) <= 0 then raise exception 'There is no share capital yet: register the incorporation first'; end if;
  if v_amt <= 0 then raise exception 'Invalid amount'; end if;
  if erp.equity_bal(v_company, v_src, v_date) < v_amt then
    raise exception 'Not enough % to convert into capital (balance %)', case v_src when '113' then 'voluntary reserves' else 'share premium' end, erp.equity_bal(v_company, v_src, v_date);
  end if;
  select g.id into v_acc from erp.gl_accounts g where g.company_id = v_company and g.account_type = 'posting' and g.account_no like v_src || '%'
  order by (select coalesce(sum(l.credit - l.debit), 0) from erp.journal_lines l where l.gl_account_id = g.id) desc limit 1;
  e1 := erp.equity_entry(v_company, v_date, 'Ampliación de capital con cargo a ' || case v_src when '113' then 'reservas' else 'la prima de emisión' end, v_code,
          jsonb_build_array(erp.equity_line(v_acc, v_amt, 0), erp.equity_line(erp.adjust_account(v_company, '100', 'Capital social'), 0, v_amt)));
  return erp.equity_save(v_company, v_code, 'reserves_to_capital', v_date, 'Ampliación de capital con cargo a reservas', p,
    jsonb_build_object('amount', v_amt, 'source', v_src), array[e1]);
end $$;

-- 8) Dividendo pasivo: exigir lo no desembolsado y, si se dice, cobrarlo: p = { company_id, date, amount, paid?, bank_account_no? }
create or replace function erp.equity_call(p jsonb)
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare
  v_company uuid := (p->>'company_id')::uuid; v_date date := (p->>'date')::date;
  v_amt numeric := round(coalesce((p->>'amount')::numeric, 0), 2); v_code text; a_5580 uuid; v_pending numeric; e1 uuid; e2 uuid;
begin
  v_code := erp.equity_start(v_company, v_date);
  v_pending := -erp.equity_bal(v_company, '1030', v_date);
  if v_amt <= 0 or v_amt > v_pending then raise exception 'The call must be between 0 and the uncalled capital (%)', v_pending; end if;
  a_5580 := erp.adjust_account(v_company, '5580', 'Socios por desembolsos exigidos sobre acciones o participaciones ordinarias');
  e1 := erp.equity_entry(v_company, v_date, 'Dividendo pasivo · se exige a los socios', v_code,
          jsonb_build_array(erp.equity_line(a_5580, v_amt, 0),
            erp.equity_line((select id from erp.gl_accounts where company_id = v_company and account_type = 'posting' and account_no like '1030%' order by account_no limit 1), 0, v_amt)));
  if coalesce((p->>'paid')::boolean, false) then
    e2 := erp.equity_entry(v_company, v_date, 'Dividendo pasivo · cobro', v_code,
            jsonb_build_array(erp.equity_line(erp.equity_bank(v_company, p->>'bank_account_no'), v_amt, 0), erp.equity_line(a_5580, 0, v_amt)));
  end if;
  return erp.equity_save(v_company, v_code, 'call', v_date, 'Dividendo pasivo', p,
    jsonb_build_object('amount', v_amt, 'paid', e2 is not null, 'uncalled_after', v_pending - v_amt), array[e1, e2]);
end $$;

-- 9) Reparto del resultado del ejercicio anterior (lo acuerda la junta): propuesta sin contabilizar
--    p = { company_id, date, dividend?, legal_reserve? (no menos de la obligatoria), offset_losses? (por defecto, todas las posibles) }
create or replace function erp.equity_distribution_preview(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = erp, public as $$
declare
  v_company uuid := (p->>'company_id')::uuid; v_date date := (p->>'date')::date;
  v_form text; v_res numeric; v_cap numeric; v_res112 numeric; v_losses numeric; v_interim numeric; v_nw numeric;
  v_offset numeric; v_legal_min numeric; v_legal numeric; v_div numeric; v_avail numeric; v_vol numeric; v_warn jsonb := '[]'; v_ok boolean := true;
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
  -- beneficio: primero las pérdidas pendientes (art. 273.2), después la reserva legal (art. 274 / 4.2), el dividendo y el resto
  v_offset := least(v_losses, v_res, coalesce((p->>'offset_losses')::numeric, v_losses));
  v_legal_min := erp.equity_legal_reserve(v_form, v_cap, v_res112, v_res);
  v_legal := round(coalesce((p->>'legal_reserve')::numeric, v_legal_min), 2);
  if v_legal < v_legal_min then v_ok := false; v_warn := v_warn || jsonb_build_object('code', 'legal_reserve_below_min', 'min', v_legal_min); end if;
  v_avail := v_res - v_offset - v_legal;
  v_vol := v_avail - v_div;
  if v_div < v_interim then v_ok := false; v_warn := v_warn || jsonb_build_object('code', 'dividend_below_interim', 'interim', v_interim); end if;
  if v_vol < 0 then v_ok := false; v_warn := v_warn || jsonb_build_object('code', 'dividend_above_available', 'available', v_avail); end if;
  -- art. 273.2: después del reparto, el patrimonio neto no puede quedar por debajo del capital; y sin dividendo mientras
  -- las pérdidas pendientes lo dejen por debajo
  if v_div > 0 and (v_nw - v_div < v_cap or v_losses - v_offset > 0) then
    v_ok := false; v_warn := v_warn || jsonb_build_object('code', 'net_worth_below_capital', 'net_worth_after', v_nw - v_div, 'capital', v_cap);
  end if;
  if v_losses > 0 and v_offset < v_losses then v_warn := v_warn || jsonb_build_object('code', 'losses_left', 'left', v_losses - v_offset); end if;
  return jsonb_build_object('result', v_res, 'loss', 0, 'offset_losses', v_offset, 'legal_reserve', v_legal, 'legal_reserve_min', v_legal_min,
    'dividend', v_div, 'interim', v_interim, 'complementary', v_div - v_interim, 'voluntary', v_vol, 'available', v_avail,
    'net_worth_before', v_nw, 'net_worth_after', v_nw - v_div, 'capital', v_cap, 'legal_reserve_before', v_res112,
    'low_capital_sl', v_form = 'sl' and v_cap < 3000, 'ok', v_ok, 'warnings', v_warn, 'legal_form', v_form);
end $$;

create or replace function erp.equity_distribution(p jsonb)
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare
  v_company uuid := (p->>'company_id')::uuid; v_date date := (p->>'date')::date; v_code text; g jsonb; v_res numeric; e1 uuid;
  v_lines jsonb; a_129 uuid; a_121 uuid;
begin
  v_code := erp.equity_start(v_company, v_date);
  g := erp.equity_distribution_preview(p);
  if (g->>'result')::numeric = 0 then raise exception 'There is no result to distribute on %: close the previous year first', v_date; end if;
  if not (g->>'ok')::boolean then
    raise exception 'The distribution is not valid: %', (select string_agg(w->>'code', ', ') from jsonb_array_elements(g->'warnings') w where w->>'code' <> 'losses_left');
  end if;
  v_res := (g->>'result')::numeric;
  select g2.id into a_129 from erp.gl_accounts g2 where g2.company_id = v_company and g2.account_type = 'posting' and g2.account_no like '129%'
  order by (select abs(coalesce(sum(l.credit - l.debit), 0)) from erp.journal_lines l where l.gl_account_id = g2.id) desc limit 1;
  if v_res < 0 then
    a_121 := erp.adjust_account(v_company, '121', 'Resultados negativos de ejercicios anteriores');
    v_lines := jsonb_build_array(erp.equity_line(a_121, -v_res, 0), erp.equity_line(a_129, 0, -v_res));
  else
    v_lines := jsonb_build_array(erp.equity_line(a_129, v_res, 0));
    if (g->>'offset_losses')::numeric > 0 then
      v_lines := v_lines || erp.equity_line((select id from erp.gl_accounts where company_id = v_company and account_type = 'posting' and account_no like '121%' order by account_no limit 1), 0, (g->>'offset_losses')::numeric);
    end if;
    if (g->>'legal_reserve')::numeric > 0 then v_lines := v_lines || erp.equity_line(erp.adjust_account(v_company, '112', 'Reserva legal'), 0, (g->>'legal_reserve')::numeric); end if;
    if (g->>'interim')::numeric > 0 then
      v_lines := v_lines || erp.equity_line((select id from erp.gl_accounts where company_id = v_company and account_type = 'posting' and account_no like '557%' order by account_no limit 1), 0, (g->>'interim')::numeric);
    end if;
    if (g->>'complementary')::numeric > 0 then v_lines := v_lines || erp.equity_line(erp.adjust_account(v_company, '526', 'Dividendo activo a pagar'), 0, (g->>'complementary')::numeric); end if;
    if (g->>'voluntary')::numeric > 0 then v_lines := v_lines || erp.equity_line(erp.adjust_account(v_company, '113', 'Reservas voluntarias'), 0, (g->>'voluntary')::numeric); end if;
  end if;
  e1 := erp.equity_entry(v_company, v_date, 'Distribución del resultado (acuerdo de la junta)', v_code, v_lines);
  return erp.equity_save(v_company, v_code, 'distribution', v_date, 'Distribución del resultado', p, g, array[e1]);
end $$;

-- 10) Dividendo a cuenta (art. 277 LSC): p = { company_id, date, amount, estimated_tax? (por defecto, el 25 % del resultado) }
create or replace function erp.equity_interim_preview(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = erp, public as $$
declare
  v_company uuid := (p->>'company_id')::uuid; v_date date := (p->>'date')::date; v_form text;
  v_result numeric; v_losses numeric; v_tax numeric; v_legal numeric; v_max numeric; v_amt numeric; v_cash numeric; v_paid numeric; v_warn jsonb := '[]';
begin
  if not erp.can_read(v_company) then raise exception 'No permission to read this company'; end if;
  select legal_form into v_form from erp.companies where id = v_company;
  v_result := erp.equity_bal(v_company, '6', v_date) + erp.equity_bal(v_company, '7', v_date);   -- antes de impuestos (sin 630)
  v_result := v_result - erp.equity_bal(v_company, '630', v_date);
  v_losses := -erp.equity_bal(v_company, '121', v_date);
  v_tax := round(coalesce((p->>'estimated_tax')::numeric, greatest(v_result, 0) * 0.25), 2);
  v_legal := erp.equity_legal_reserve(v_form, erp.equity_bal(v_company, '100', v_date), erp.equity_bal(v_company, '112', v_date), v_result - v_tax);
  v_paid := -erp.equity_bal(v_company, '557', v_date);   -- dividendos a cuenta ya acordados este ejercicio
  v_max := greatest(0, v_result - v_losses - v_tax - v_legal - v_paid);
  v_amt := round(coalesce((p->>'amount')::numeric, 0), 2);
  v_cash := -erp.equity_bal(v_company, '57', v_date);
  if v_amt > v_max then v_warn := v_warn || jsonb_build_object('code', 'interim_above_limit', 'max', v_max); end if;
  if v_amt > v_cash then v_warn := v_warn || jsonb_build_object('code', 'interim_no_liquidity', 'cash', v_cash); end if;
  return jsonb_build_object('result_since_close', v_result, 'prior_losses', v_losses, 'estimated_tax', v_tax, 'legal_reserve', v_legal,
    'already_paid', v_paid, 'max', v_max, 'amount', v_amt, 'cash', v_cash, 'ok', v_amt > 0 and jsonb_array_length(v_warn) = 0, 'warnings', v_warn);
end $$;

create or replace function erp.equity_interim_dividend(p jsonb)
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare v_company uuid := (p->>'company_id')::uuid; v_date date := (p->>'date')::date; v_code text; g jsonb; e1 uuid; v_amt numeric;
begin
  v_code := erp.equity_start(v_company, v_date);
  g := erp.equity_interim_preview(p);
  v_amt := (g->>'amount')::numeric;
  if v_amt <= 0 then raise exception 'Invalid amount'; end if;
  if not (g->>'ok')::boolean then
    raise exception 'The interim dividend is not valid: % (art. 277 LSC)', (select string_agg(w->>'code', ', ') from jsonb_array_elements(g->'warnings') w);
  end if;
  e1 := erp.equity_entry(v_company, v_date, 'Dividendo a cuenta (acuerdo del órgano de administración)', v_code,
          jsonb_build_array(erp.equity_line(erp.adjust_account(v_company, '557', 'Dividendo activo a cuenta'), v_amt, 0),
                            erp.equity_line(erp.adjust_account(v_company, '526', 'Dividendo activo a pagar'), 0, v_amt)));
  return erp.equity_save(v_company, v_code, 'interim_dividend', v_date, 'Dividendo a cuenta', p, g, array[e1]);
end $$;

-- 11) Pago del dividendo: p = { company_id, date, amount? (por defecto, todo lo pendiente), withholding_pct? (19),
--     no_withholding_reason? (sin retención: el motivo), bank_account_no? }
create or replace function erp.equity_dividend_payment(p jsonb)
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare
  v_company uuid := (p->>'company_id')::uuid; v_date date := (p->>'date')::date; v_code text; v_pending numeric; v_amt numeric;
  v_pct numeric; v_wh numeric; e1 uuid; v_reason text := nullif(btrim(p->>'no_withholding_reason'), '');
begin
  v_code := erp.equity_start(v_company, v_date);
  v_pending := erp.equity_bal(v_company, '526', v_date);
  v_amt := round(coalesce((p->>'amount')::numeric, v_pending), 2);
  if v_amt <= 0 or v_amt > v_pending then raise exception 'The payment must be between 0 and the dividend payable (%)', v_pending; end if;
  v_pct := case when v_reason is not null then 0 else coalesce((p->>'withholding_pct')::numeric, 19) end;
  if v_pct <> 0 and v_pct <> 19 then raise exception 'The withholding on dividends is 19 %% (art. 101.4 LIRPF) or none with its reason'; end if;
  if v_pct = 0 and v_reason is null then raise exception 'Without withholding, say why (e.g. exemption of art. 21 LIS)'; end if;
  v_wh := round(v_amt * v_pct / 100, 2);
  e1 := erp.equity_entry(v_company, v_date, 'Pago del dividendo' || case when v_wh > 0 then ' (retención del 19 %, modelo 123)' else ' (sin retención: ' || v_reason || ')' end, v_code,
          jsonb_build_array(erp.equity_line((select id from erp.gl_accounts where company_id = v_company and account_type = 'posting' and account_no like '526%' order by account_no limit 1), v_amt, 0),
            erp.equity_line(case when v_wh > 0 then erp.adjust_account(v_company, '47512', 'HP acreedora por retenciones de dividendos (modelo 123)') end, 0, v_wh),
            erp.equity_line(erp.equity_bank(v_company, p->>'bank_account_no'), 0, v_amt - v_wh)));
  return erp.equity_save(v_company, v_code, 'dividend_payment', v_date, 'Pago del dividendo', p,
    jsonb_build_object('gross', v_amt, 'withholding', v_wh, 'net', v_amt - v_wh, 'pending_after', v_pending - v_amt), array[e1]);
end $$;

-- 12) Compensar pérdidas con reservas voluntarias: p = { company_id, date, amount }
create or replace function erp.equity_loss_offset(p jsonb)
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare v_company uuid := (p->>'company_id')::uuid; v_date date := (p->>'date')::date; v_code text; v_amt numeric; v_losses numeric; v_vol numeric; e1 uuid;
begin
  v_code := erp.equity_start(v_company, v_date);
  v_amt := round(coalesce((p->>'amount')::numeric, 0), 2);
  v_losses := -erp.equity_bal(v_company, '121', v_date); v_vol := erp.equity_bal(v_company, '113', v_date);
  if v_amt <= 0 or v_amt > v_losses then raise exception 'The amount must be between 0 and the pending losses (%)', v_losses; end if;
  if v_amt > v_vol then raise exception 'Not enough voluntary reserves (balance %)', v_vol; end if;
  e1 := erp.equity_entry(v_company, v_date, 'Compensación de pérdidas con reservas voluntarias', v_code,
          jsonb_build_array(erp.equity_line((select g.id from erp.gl_accounts g where g.company_id = v_company and g.account_type = 'posting' and g.account_no like '113%'
                                             order by (select coalesce(sum(l.credit - l.debit), 0) from erp.journal_lines l where l.gl_account_id = g.id) desc limit 1), v_amt, 0),
            erp.equity_line((select id from erp.gl_accounts where company_id = v_company and account_type = 'posting' and account_no like '121%' order by account_no limit 1), 0, v_amt)));
  return erp.equity_save(v_company, v_code, 'loss_offset', v_date, 'Compensación de pérdidas', p,
    jsonb_build_object('amount', v_amt, 'losses_after', v_losses - v_amt), array[e1]);
end $$;

-- 13) Reducir el capital para compensar pérdidas (art. 320 y 322 LSC): p = { company_id, date, amount }
create or replace function erp.equity_capital_reduction(p jsonb)
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare
  v_company uuid := (p->>'company_id')::uuid; v_date date := (p->>'date')::date; v_code text; v_amt numeric; v_losses numeric;
  v_cap numeric; v_form text; e1 uuid;
begin
  v_code := erp.equity_start(v_company, v_date);
  select legal_form into v_form from erp.companies where id = v_company;
  v_amt := round(coalesce((p->>'amount')::numeric, 0), 2);
  v_losses := -erp.equity_bal(v_company, '121', v_date); v_cap := erp.equity_bal(v_company, '100', v_date);
  if v_amt <= 0 or v_amt > v_losses then raise exception 'The reduction must be between 0 and the pending losses (%)', v_losses; end if;
  if erp.equity_bal(v_company, '113', v_date) > 0 then raise exception 'Use the voluntary reserves first: capital cannot be reduced for losses while there are reserves (art. 322 LSC)'; end if;
  if erp.equity_bal(v_company, '112', v_date) > round((v_cap - v_amt) * 0.10, 2) then
    raise exception 'The legal reserve would exceed 10 %% of the new capital: use it first (art. 322 LSC)';
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

-- 14) Deshacer la última operación (contraasientos de todos sus asientos)
create or replace function erp.equity_cancel(p_operation uuid)
returns void language plpgsql security definer set search_path = erp, public as $$
declare r erp.equity_operations; v_e uuid;
begin
  select * into r from erp.equity_operations where id = p_operation;
  if not found then raise exception 'Equity operation not found'; end if;
  if not erp.can_write(r.company_id) then raise exception 'No permission to change equity operations in this company'; end if;
  if r.status <> 'posted' then raise exception 'The operation is already cancelled'; end if;
  perform pg_advisory_xact_lock(hashtext('equity/' || r.company_id));
  if exists (select 1 from erp.equity_operations x where x.company_id = r.company_id and x.status = 'posted' and x.code > r.code) then
    raise exception 'Undo the later equity operations first (from the last one)';
  end if;
  if exists (select 1 from erp.fiscal_years f where f.company_id = r.company_id and r.op_date between f.starting_date and f.ending_date and f.status = 'closed') then
    raise exception 'The year of this operation is closed: reopen it first';
  end if;
  foreach v_e in array r.entry_ids loop
    perform erp.adjust_reverse(v_e, r.op_date, 'Deshacer ' || r.code);
  end loop;
  update erp.equity_operations set status = 'cancelled' where id = r.id;
end $$;

-- 15) Forma jurídica (solo el admin, y antes de la primera operación)
create or replace function erp.set_legal_form(p_company uuid, p_form text)
returns void language plpgsql security definer set search_path = erp, public as $$
begin
  if not erp.is_admin(p_company) then raise exception 'Only the company admin can change the legal form'; end if;
  if p_form not in ('sa', 'sl') then raise exception 'Invalid legal form: %', p_form; end if;
  if exists (select 1 from erp.equity_operations where company_id = p_company and status = 'posted') then
    raise exception 'The company already has equity operations: undo them before changing the legal form';
  end if;
  update erp.companies set legal_form = p_form where id = p_company;
end $$;

revoke execute on function erp.equity_bal(uuid, text, date), erp.equity_bank(uuid, text), erp.equity_entry(uuid, date, text, text, jsonb),
  erp.equity_start(uuid, date), erp.equity_save(uuid, text, text, date, text, jsonb, jsonb, uuid[]) from anon, public, authenticated;
revoke execute on function erp.equity_status(uuid, date), erp.equity_incorporation(jsonb), erp.equity_capital_increase(jsonb),
  erp.equity_reserves_to_capital(jsonb), erp.equity_call(jsonb), erp.equity_distribution_preview(jsonb), erp.equity_distribution(jsonb),
  erp.equity_interim_preview(jsonb), erp.equity_interim_dividend(jsonb), erp.equity_dividend_payment(jsonb), erp.equity_loss_offset(jsonb),
  erp.equity_capital_reduction(jsonb), erp.equity_cancel(uuid), erp.set_legal_form(uuid, text) from anon, public;
grant execute on function erp.equity_status(uuid, date), erp.equity_incorporation(jsonb), erp.equity_capital_increase(jsonb),
  erp.equity_reserves_to_capital(jsonb), erp.equity_call(jsonb), erp.equity_distribution_preview(jsonb), erp.equity_distribution(jsonb),
  erp.equity_interim_preview(jsonb), erp.equity_interim_dividend(jsonb), erp.equity_dividend_payment(jsonb), erp.equity_loss_offset(jsonb),
  erp.equity_capital_reduction(jsonb), erp.equity_cancel(uuid), erp.set_legal_form(uuid, text) to authenticated;

-- 16) Módulo propio: no se anula desde el diario, no es un asiento manual, tiene su origen en el diario y en el
--     auditor, y se borra con la empresa (versiones de la 0058; cambia solo lo marcado «v0.42.0»)
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
