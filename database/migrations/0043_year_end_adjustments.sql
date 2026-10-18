-- =====================================================================
-- 0043 · FIN DE EJERCICIO I: periodificaciones y deterioro de clientes · v0.36.0
-- ---------------------------------------------------------------------
-- Ajustes de cierre del PGC 2007 (marco conceptual: principio de DEVENGO; NRV 9.ª, deterioro de créditos), como los
-- «periodos de diferimiento» de Business Central y las correcciones de valor de SAP (FI-AR), con su asiento:
--
--   PERIODIFICACIONES (cuenta de balance ↔ la propia cuenta de gasto o ingreso; se revierten en el ejercicio siguiente)
--     · gasto anticipado   (pagado este año, es del siguiente):   480  D / 6xx H
--     · ingreso anticipado (cobrado este año, es del siguiente):  7xx  D / 485 H
--     · gasto devengado sin factura (factura pendiente de recibir): 6xx D / 4009 H
--     · ingreso devengado sin factura (pendiente de formalizar):    4309 D / 7xx H
--     El importe se puede calcular por meses (el primer mes por días, como la amortización) desde el total y el
--     periodo que cubre. La REVERSIÓN es un asiento nuevo (no una anulación): el gasto o el ingreso pasa al año en que
--     se devenga.
--
--   DETERIORO DE CLIENTES (la deuda sigue en la 430 con su partida abierta; la 490 la corrige)
--     · individual, sobre lo pendiente de una factura:  694 D / 490 H
--     · global, por tramos de antigüedad:               694 D / 490 H
--     · reversión (cobro, o nueva estimación):          490 D / 794 H
--     · insolvencia firme:  650 D / 430 H (cierra la partida abierta como un cobro sin banco)
--                           + 490 D / 794 H (se aplica el deterioro que tenía)
--     Aviso fiscal (Ley 27/2014 del IS): el deterioro individual es deducible desde los 6 meses del vencimiento
--     (art. 13.1.a); el global no lo es (art. 13.1), salvo para las empresas de reducida dimensión, hasta el 1 % de los
--     deudores (art. 104).
--
-- Cuentas CONTROLADAS (0036): 480, 485, 4009 y 4309 por Periodificaciones; 490 por Deterioro. Re-ejecutable.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Periodificaciones
-- ---------------------------------------------------------------------
create table if not exists erp.accruals (
  id                  uuid primary key default gen_random_uuid(),
  company_id          uuid not null references erp.companies(id) on delete cascade,
  code                text not null,
  kind                text not null check (kind in ('prepaid_expense', 'deferred_income', 'accrued_expense', 'accrued_income')),
  description         text not null,
  pl_account_id       uuid not null references erp.gl_accounts(id),   -- 6xx / 7xx
  balance_account_id  uuid not null references erp.gl_accounts(id),   -- 480 / 485 / 4009 / 4309
  cutoff_date         date not null,                                  -- fecha del ajuste (normalmente el cierre)
  amount              numeric(15,2) not null check (amount > 0),
  total_amount        numeric(15,2),                                  -- si se calcula: importe total del periodo
  coverage_start      date,
  coverage_months     int check (coverage_months > 0),
  invoice_id          uuid references erp.invoices(id),
  entry_id            uuid not null references erp.journal_entries(id),
  status              text not null default 'active' check (status in ('active', 'reversed', 'cancelled')),
  reversal_date       date,
  reversal_entry_id   uuid references erp.journal_entries(id),
  cancel_entry_id     uuid references erp.journal_entries(id),
  created_at          timestamptz not null default now(),
  unique (company_id, code)
);
comment on table erp.accruals is 'Year-end accruals and deferrals (PGC 480/485/4009/4309), reversed in the next period (BC: deferral templates).';
create index if not exists accruals_company_idx  on erp.accruals (company_id, cutoff_date);
create index if not exists accruals_pl_idx       on erp.accruals (pl_account_id);
create index if not exists accruals_balance_idx  on erp.accruals (balance_account_id);
create index if not exists accruals_invoice_idx  on erp.accruals (invoice_id);
create index if not exists accruals_entry_idx    on erp.accruals (entry_id);
create index if not exists accruals_rev_idx      on erp.accruals (reversal_entry_id);
create index if not exists accruals_cancel_idx   on erp.accruals (cancel_entry_id);

-- ---------------------------------------------------------------------
-- 2) Deterioros de clientes e insolvencias firmes
-- ---------------------------------------------------------------------
create table if not exists erp.receivable_impairments (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null references erp.companies(id) on delete cascade,
  code             text not null,
  method           text not null check (method in ('individual', 'global')),
  invoice_id       uuid references erp.invoices(id),            -- individual
  partner_id       uuid references erp.business_partners(id),   -- individual
  impair_date      date not null,
  basis            numeric(15,2) not null,                      -- pendiente sobre el que se calcula
  pct              numeric(5,2),                                -- individual
  amount           numeric(15,2) not null check (amount > 0),
  details          jsonb not null default '[]',                 -- global: tramos de antigüedad
  warnings         jsonb not null default '[]',
  entry_id         uuid not null references erp.journal_entries(id),
  status           text not null default 'active' check (status in ('active', 'reversed', 'written_off', 'cancelled')),
  end_date         date,                                        -- reversión o insolvencia
  end_entry_id     uuid references erp.journal_entries(id),
  cancel_entry_id  uuid references erp.journal_entries(id),
  created_at       timestamptz not null default now(),
  unique (company_id, code),
  check ((method = 'individual') = (invoice_id is not null))
);
comment on table erp.receivable_impairments is 'Impairment of trade receivables (PGC 490/694/794), individual or global (SAP: value adjustments).';
create index if not exists impairments_company_idx on erp.receivable_impairments (company_id, impair_date);
create unique index if not exists impairments_one_active on erp.receivable_impairments (invoice_id)
  where status = 'active' and method = 'individual';
create unique index if not exists impairments_one_global on erp.receivable_impairments (company_id)
  where status = 'active' and method = 'global';
create index if not exists impairments_partner_idx on erp.receivable_impairments (partner_id);
create index if not exists impairments_entry_idx   on erp.receivable_impairments (entry_id);
create index if not exists impairments_end_idx     on erp.receivable_impairments (end_entry_id);
create index if not exists impairments_cancel_idx  on erp.receivable_impairments (cancel_entry_id);

create table if not exists erp.receivable_writeoffs (
  id                  uuid primary key default gen_random_uuid(),
  company_id          uuid not null references erp.companies(id) on delete cascade,
  invoice_id          uuid not null references erp.invoices(id),
  partner_id          uuid not null references erp.business_partners(id),
  writeoff_date       date not null,
  amount              numeric(15,2) not null check (amount > 0),
  impairment_id       uuid references erp.receivable_impairments(id),
  impairment_applied  numeric(15,2) not null default 0,
  entry_id            uuid not null references erp.journal_entries(id),
  payment_id          uuid not null references erp.payments(id),
  cancel_entry_id     uuid references erp.journal_entries(id),
  created_at          timestamptz not null default now()
);
comment on table erp.receivable_writeoffs is 'Definitive bad debts (PGC 650): close the open item like a collection without cash.';
create index if not exists writeoffs_company_idx    on erp.receivable_writeoffs (company_id);
create index if not exists writeoffs_invoice_idx    on erp.receivable_writeoffs (invoice_id);
create index if not exists writeoffs_partner_idx    on erp.receivable_writeoffs (partner_id);
create index if not exists writeoffs_impairment_idx on erp.receivable_writeoffs (impairment_id);
create index if not exists writeoffs_entry_idx      on erp.receivable_writeoffs (entry_id);
create index if not exists writeoffs_payment_idx    on erp.receivable_writeoffs (payment_id);
create index if not exists writeoffs_cancel_idx     on erp.receivable_writeoffs (cancel_entry_id);

alter table erp.accruals enable row level security;
alter table erp.receivable_impairments enable row level security;
alter table erp.receivable_writeoffs enable row level security;
drop policy if exists read on erp.accruals;
drop policy if exists read on erp.receivable_impairments;
drop policy if exists read on erp.receivable_writeoffs;
create policy read on erp.accruals for select to authenticated using (erp.can_read(company_id));
create policy read on erp.receivable_impairments for select to authenticated using (erp.can_read(company_id));
create policy read on erp.receivable_writeoffs for select to authenticated using (erp.can_read(company_id));
revoke all on erp.accruals, erp.receivable_impairments, erp.receivable_writeoffs from anon, public;
grant select on erp.accruals, erp.receivable_impairments, erp.receivable_writeoffs to authenticated;   -- se escriben con las funciones

-- ---------------------------------------------------------------------
-- 3) Ayudas: subcuenta de un prefijo (la crea si falta) y fecha de un ejercicio
-- ---------------------------------------------------------------------
create or replace function erp.adjust_account(p_company uuid, p_prefix text, p_name text)
returns uuid language plpgsql security definer set search_path = erp, public as $$
declare
  v_no text := rpad(p_prefix, (select posting_account_digits from erp.companies where id = p_company) - 1, '0') || '1';
  v_id uuid;
begin
  select id into v_id from erp.gl_accounts where company_id = p_company and account_no = v_no;
  if v_id is null then v_id := erp.create_posting_account(p_company, v_no, p_name); end if;
  return v_id;
end $$;

create or replace function erp.adjust_fiscal_year(p_company uuid, p_date date)
returns uuid language plpgsql stable as $$
declare v uuid;
begin
  select id into v from erp.fiscal_years where company_id = p_company and p_date between starting_date and ending_date;
  if v is null then raise exception 'No fiscal year for date %: create it first', p_date; end if;
  return v;
end $$;

-- Parte de un importe que corresponde al periodo transcurrido hasta una fecha (por meses; el primer mes, por días)
create or replace function erp.accrual_elapsed(p_total numeric, p_start date, p_months int, p_date date)
returns numeric language sql immutable as $$
  select erp.asset_accumulated_at(p_total, 0, p_months, p_start, p_date);
$$;

-- Asiento de dos líneas del módulo (el motor marca que es suyo)
create or replace function erp.adjust_post(p_company uuid, p_date date, p_desc text, p_doc text,
                                            p_debit uuid, p_credit uuid, p_amount numeric, p_partner uuid default null)
returns uuid language plpgsql security definer set search_path = erp, public as $$
declare v_entry uuid;
begin
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no)
  values (p_company, erp.adjust_fiscal_year(p_company, p_date), p_date, left(p_desc, 250), left(p_doc, 60))
  returning id into v_entry;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, partner_id) values
    (v_entry, p_company, 1, p_debit, p_amount, 0, null),
    (v_entry, p_company, 2, p_credit, 0, p_amount, p_partner);
  return v_entry;
end $$;

create or replace function erp.adjust_finish(p_entry uuid)
returns int language plpgsql security definer set search_path = erp, public as $$
declare v int;
begin
  perform set_config('erp.adjust_engine', 'on', true);
  v := erp.post_entry(p_entry);
  perform set_config('erp.adjust_engine', 'off', true);
  return v;
end $$;

create or replace function erp.adjust_reverse(p_entry uuid, p_date date, p_reason text)
returns int language plpgsql security definer set search_path = erp, public as $$
declare v int;
begin
  perform set_config('erp.adjust_engine', 'on', true);
  perform set_config('erp.payment_engine', 'on', true);
  v := erp.reverse_entry(p_entry, p_date, p_reason);
  perform set_config('erp.payment_engine', 'off', true);
  perform set_config('erp.adjust_engine', 'off', true);
  return v;
end $$;

-- ---------------------------------------------------------------------
-- 4) Periodificar
--   p: { company_id, kind, description, pl_account_no, cutoff_date,
--        amount  ─o bien─  total_amount + coverage_start + coverage_months,
--        balance_account_no (opcional: subcuenta de 480 / 485 / 4009 / 4309), invoice_id (opcional) }
--   Con el total: gasto o ingreso ANTICIPADO = lo que queda del periodo tras el corte;
--                 DEVENGADO sin factura      = lo transcurrido hasta el corte.
-- ---------------------------------------------------------------------
create or replace function erp.create_accrual(p jsonb)
returns table (accrual_id uuid, code text, entry_no int, amount numeric)
language plpgsql security definer set search_path = erp, public as $$
declare
  v_company uuid := (p->>'company_id')::uuid;
  v_kind    text := p->>'kind';
  v_date    date := (p->>'cutoff_date')::date;
  v_prefix  text;
  v_pl      erp.gl_accounts;
  v_bal     erp.gl_accounts;
  v_total   numeric := round((p->>'total_amount')::numeric, 2);
  v_start   date := (p->>'coverage_start')::date;
  v_months  int := (p->>'coverage_months')::int;
  v_amount  numeric;
  v_inv     erp.invoices;
  v_code    text;
  v_entry   uuid;
  v_no      int;
  v_id      uuid;
  v_desc    text := btrim(coalesce(p->>'description', ''));
begin
  if not erp.can_write(v_company) then raise exception 'No permission to register accruals in this company'; end if;
  v_prefix := case v_kind when 'prepaid_expense' then '480' when 'deferred_income' then '485'
                          when 'accrued_expense' then '4009' when 'accrued_income' then '4309' end;
  if v_prefix is null then raise exception 'Invalid accrual type: %', v_kind; end if;
  if v_desc = '' then raise exception 'The accrual needs a description'; end if;
  if v_date is null then raise exception 'The cut-off date is required'; end if;

  select * into v_pl from erp.gl_accounts
  where company_id = v_company and account_no = p->>'pl_account_no' and account_type = 'posting';
  if not found or left(v_pl.account_no, 1) <> (case when v_kind like '%expense' then '6' else '7' end) then
    raise exception 'Choose the % account (group %)', case when v_kind like '%expense' then 'expense' else 'income' end,
      case when v_kind like '%expense' then '6' else '7' end;
  end if;

  if p->>'balance_account_no' is not null then
    select * into v_bal from erp.gl_accounts
    where company_id = v_company and account_no = p->>'balance_account_no' and account_type = 'posting';
    if not found or v_bal.account_no not like v_prefix || '%' then raise exception 'The balance account must be a % subaccount', v_prefix; end if;
  else
    v_id := erp.adjust_account(v_company, v_prefix, case v_prefix
      when '480' then 'Gastos anticipados' when '485' then 'Ingresos anticipados'
      when '4009' then 'Proveedores, facturas pendientes de recibir o de formalizar'
      else 'Clientes, facturas pendientes de formalizar' end);
    select * into v_bal from erp.gl_accounts where id = v_id;   -- (la función, fuera del where: crea la cuenta)
  end if;

  if p->>'invoice_id' is not null then
    select * into v_inv from erp.invoices i where i.id = (p->>'invoice_id')::uuid and i.company_id = v_company;
    if not found then raise exception 'The invoice must belong to this company'; end if;
  end if;

  -- Importe: dado, o calculado por meses desde el total
  if v_total is not null then
    if v_total <= 0 then raise exception 'The total amount must be greater than zero'; end if;
    if v_start is null or v_months is null or v_months <= 0 then
      raise exception 'To calculate the accrual give the start date and the months the amount covers';
    end if;
    v_amount := case when v_kind in ('prepaid_expense', 'deferred_income')
                     then v_total - erp.accrual_elapsed(v_total, v_start, v_months, v_date)
                     else erp.accrual_elapsed(v_total, v_start, v_months, v_date) end;
    if v_amount <= 0 then
      raise exception 'Nothing to accrue at %: the period % the cut-off date', v_date,
        case when v_kind in ('prepaid_expense', 'deferred_income') then 'ends before' else 'starts after' end;
    end if;
  else
    v_amount := round((p->>'amount')::numeric, 2);
    v_start := null; v_months := null;
    if v_amount is null or v_amount <= 0 then raise exception 'The amount must be greater than zero'; end if;
  end if;

  select 'PER-' || lpad((count(*) + 1)::text, 4, '0') into v_code from erp.accruals a where a.company_id = v_company;
  v_entry := case
    when v_kind in ('prepaid_expense', 'accrued_income')
      then erp.adjust_post(v_company, v_date, 'Periodificación ' || v_code || ' · ' || v_desc, v_inv.invoice_no, v_bal.id, v_pl.id, v_amount)
    else erp.adjust_post(v_company, v_date, 'Periodificación ' || v_code || ' · ' || v_desc, v_inv.invoice_no, v_pl.id, v_bal.id, v_amount) end;
  insert into erp.accruals (company_id, code, kind, description, pl_account_id, balance_account_id, cutoff_date, amount,
                            total_amount, coverage_start, coverage_months, invoice_id, entry_id)
  values (v_company, v_code, v_kind, v_desc, v_pl.id, v_bal.id, v_date, v_amount,
          v_total, v_start, v_months, v_inv.id, v_entry)
  returning id into v_id;
  v_no := erp.adjust_finish(v_entry);
  accrual_id := v_id; code := v_code; entry_no := v_no; amount := v_amount;
  return next;
end $$;

-- Revertir una periodificación (asiento nuevo, al revés; por defecto el día siguiente al corte)
create or replace function erp.reverse_accrual(p_accrual uuid, p_date date default null)
returns int language plpgsql security definer set search_path = erp, public as $$
declare a erp.accruals; v_date date; v_entry uuid; v_no int;
begin
  select * into a from erp.accruals where id = p_accrual;
  if not found then raise exception 'Accrual not found'; end if;
  if not erp.can_write(a.company_id) then raise exception 'No permission to register accruals in this company'; end if;
  if a.status <> 'active' then raise exception 'Accrual % is not pending reversal', a.code; end if;
  v_date := coalesce(p_date, a.cutoff_date + 1);
  if v_date <= a.cutoff_date then raise exception 'The reversal must be after the cut-off date (%)', a.cutoff_date; end if;
  v_entry := case
    when a.kind in ('prepaid_expense', 'accrued_income')
      then erp.adjust_post(a.company_id, v_date, 'Reversión de la periodificación ' || a.code || ' · ' || a.description, null, a.pl_account_id, a.balance_account_id, a.amount)
    else erp.adjust_post(a.company_id, v_date, 'Reversión de la periodificación ' || a.code || ' · ' || a.description, null, a.balance_account_id, a.pl_account_id, a.amount) end;
  update erp.accruals set status = 'reversed', reversal_date = v_date, reversal_entry_id = v_entry where id = a.id;
  v_no := erp.adjust_finish(v_entry);
  return v_no;
end $$;

-- Revertir todas las pendientes con corte anterior a una fecha (la apertura del ejercicio)
create or replace function erp.reverse_accruals(p_company uuid, p_date date)
returns int language plpgsql security definer set search_path = erp, public as $$
declare r record; v_n int := 0;
begin
  if not erp.can_write(p_company) then raise exception 'No permission to register accruals in this company'; end if;
  for r in select id from erp.accruals where company_id = p_company and status = 'active' and cutoff_date < p_date order by code loop
    perform erp.reverse_accrual(r.id, p_date);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- Deshacer el último paso: la reversión, si la hay; si no, la periodificación (contraasiento)
create or replace function erp.cancel_accrual(p_accrual uuid, p_date date default null)
returns int language plpgsql security definer set search_path = erp, public as $$
declare a erp.accruals; v_no int;
begin
  select * into a from erp.accruals where id = p_accrual;
  if not found then raise exception 'Accrual not found'; end if;
  if not erp.can_write(a.company_id) then raise exception 'No permission to register accruals in this company'; end if;
  if a.status = 'cancelled' then raise exception 'Accrual % is already cancelled', a.code; end if;
  if a.status = 'reversed' then
    v_no := erp.adjust_reverse(a.reversal_entry_id, coalesce(p_date, a.reversal_date), 'Reversión deshecha');
    update erp.accruals set status = 'active', reversal_date = null, reversal_entry_id = null where id = a.id;
  else
    v_no := erp.adjust_reverse(a.entry_id, coalesce(p_date, a.cutoff_date), 'Periodificación anulada');
    update erp.accruals set status = 'cancelled', cancel_entry_id = (select reversed_by from erp.journal_entries where id = a.entry_id)
    where id = a.id;
  end if;
  return v_no;
end $$;

-- ---------------------------------------------------------------------
-- 5) Deterioro individual de una factura emitida
--   p: { invoice_id, impair_date, pct (por defecto 100) }  →  { impairment_id, code, entry_no, amount, warnings }
-- ---------------------------------------------------------------------
create or replace function erp.impair_receivable(p jsonb)
returns table (impairment_id uuid, code text, entry_no int, amount numeric, warnings jsonb)
language plpgsql security definer set search_path = erp, public as $$
declare
  v_inv   erp.invoices;
  v_date  date := (p->>'impair_date')::date;
  v_pct   numeric := coalesce((p->>'pct')::numeric, 100);
  v_oi    record;
  v_amt   numeric;
  v_warn  jsonb := '[]';
  v_code  text;
  v_entry uuid;
  v_id    uuid;
  v_no    int;
begin
  select * into v_inv from erp.invoices where id = (p->>'invoice_id')::uuid;
  if not found then raise exception 'Invoice not found'; end if;
  if not erp.can_write(v_inv.company_id) then raise exception 'No permission to register impairments in this company'; end if;
  if v_inv.invoice_type <> 'sale' or v_inv.document_kind <> 'invoice' then
    raise exception 'Only issued invoices (customer receivables) can be impaired';
  end if;
  if v_date is null then raise exception 'The impairment date is required'; end if;
  if v_pct <= 0 or v_pct > 100 then raise exception 'The percentage must be between 0 and 100'; end if;
  if exists (select 1 from erp.receivable_impairments i where i.invoice_id = v_inv.id and i.status = 'active') then
    raise exception 'Invoice % is already impaired: reverse that impairment first', v_inv.invoice_no;
  end if;
  select * into v_oi from erp.open_items(v_inv.company_id, v_date) o where o.invoice_id = v_inv.id;
  if v_oi is null or v_oi.pending <= 0 then raise exception 'Invoice % has nothing pending at %', v_inv.invoice_no, v_date; end if;
  v_amt := round(v_oi.pending * v_pct / 100, 2);

  -- LIS art. 13.1.a: deducible cuando han pasado 6 meses desde el vencimiento
  if v_date < (v_oi.due_date + interval '6 months')::date then
    v_warn := v_warn || jsonb_build_object('code', 'not_deductible_6m', 'due_date', v_oi.due_date,
                                           'deductible_from', (v_oi.due_date + interval '6 months')::date);
  end if;

  select 'DET-' || lpad((count(*) + 1)::text, 4, '0') into v_code from erp.receivable_impairments i where i.company_id = v_inv.company_id;
  v_entry := erp.adjust_post(v_inv.company_id, v_date,
    'Deterioro ' || v_code || ' · factura ' || v_inv.invoice_no || ' · ' || v_oi.partner_name, v_inv.invoice_no,
    erp.adjust_account(v_inv.company_id, '694', 'Pérdidas por deterioro de créditos por operaciones comerciales'),
    erp.adjust_account(v_inv.company_id, '490', 'Deterioro de valor de créditos por operaciones comerciales'), v_amt);
  insert into erp.receivable_impairments (company_id, code, method, invoice_id, partner_id, impair_date, basis, pct, amount, warnings, entry_id)
  values (v_inv.company_id, v_code, 'individual', v_inv.id, v_inv.partner_id, v_date, v_oi.pending, v_pct, v_amt, v_warn, v_entry)
  returning id into v_id;
  v_no := erp.adjust_finish(v_entry);
  impairment_id := v_id; code := v_code; entry_no := v_no; amount := v_amt; warnings := v_warn;
  return next;
end $$;

-- ---------------------------------------------------------------------
-- 6) Deterioro global por tramos de antigüedad (sin las facturas con deterioro individual)
--   p: { company_id, impair_date, rates: { not_due, d1_90, d91_180, d181_365, d365_plus } (en %) }
-- ---------------------------------------------------------------------
create or replace function erp.global_impairment_calc(p_company uuid, p_date date, p_rates jsonb)
returns table (tier text, basis numeric, pct numeric, amount numeric)
language sql stable as $$
  with t(tier, sort) as (values ('not_due', 1), ('d1_90', 2), ('d91_180', 3), ('d181_365', 4), ('d365_plus', 5)),
  o as (
    select case when o.days_overdue = 0 then 'not_due' when o.days_overdue <= 90 then 'd1_90'
                when o.days_overdue <= 180 then 'd91_180' when o.days_overdue <= 365 then 'd181_365' else 'd365_plus' end as tier,
           o.pending
    from erp.open_items(p_company, p_date) o
    where o.invoice_type = 'sale' and o.pending > 0
      and not exists (select 1 from erp.receivable_impairments i
                      where i.invoice_id = o.invoice_id and i.status = 'active' and i.impair_date <= p_date)
  )
  select t.tier, coalesce(sum(o.pending), 0), coalesce((p_rates->>t.tier)::numeric, 0),
         round(coalesce(sum(o.pending), 0) * coalesce((p_rates->>t.tier)::numeric, 0) / 100, 2)
  from t left join o on o.tier = t.tier
  group by t.tier, t.sort order by t.sort;
$$;

create or replace function erp.impair_receivables_global(p jsonb)
returns table (impairment_id uuid, code text, entry_no int, amount numeric, warnings jsonb)
language plpgsql security definer set search_path = erp, public as $$
declare
  v_company uuid := (p->>'company_id')::uuid;
  v_date    date := (p->>'impair_date')::date;
  v_rates   jsonb := coalesce(p->'rates', '{}');
  v_details jsonb;
  v_basis   numeric;
  v_amt     numeric;
  v_warn    jsonb;
  v_code    text;
  v_entry   uuid;
  v_id      uuid;
  v_no      int;
begin
  if not erp.can_write(v_company) then raise exception 'No permission to register impairments in this company'; end if;
  if v_date is null then raise exception 'The impairment date is required'; end if;
  if exists (select 1 from jsonb_each_text(v_rates) r where r.value::numeric < 0 or r.value::numeric > 100) then
    raise exception 'The percentages must be between 0 and 100';
  end if;
  if exists (select 1 from erp.receivable_impairments i where i.company_id = v_company and i.method = 'global' and i.status = 'active') then
    raise exception 'There is already a global impairment: reverse it first (it is re-estimated each year)';
  end if;
  select jsonb_agg(to_jsonb(c)), sum(c.basis), sum(c.amount) into v_details, v_basis, v_amt
  from erp.global_impairment_calc(v_company, v_date, v_rates) c;
  if coalesce(v_amt, 0) <= 0 then raise exception 'Nothing to impair at % with these percentages', v_date; end if;

  -- LIS art. 13.1: la estimación global no es deducible; art. 104: salvo empresas de reducida dimensión, hasta el 1 %
  v_warn := jsonb_build_array(jsonb_build_object('code', 'global_not_deductible', 'erd_limit', round(v_basis * 0.01, 2)));

  select 'DET-' || lpad((count(*) + 1)::text, 4, '0') into v_code from erp.receivable_impairments i where i.company_id = v_company;
  v_entry := erp.adjust_post(v_company, v_date, 'Deterioro global ' || v_code || ' de clientes al ' || to_char(v_date, 'DD/MM/YYYY'), null,
    erp.adjust_account(v_company, '694', 'Pérdidas por deterioro de créditos por operaciones comerciales'),
    erp.adjust_account(v_company, '490', 'Deterioro de valor de créditos por operaciones comerciales'), v_amt);
  insert into erp.receivable_impairments (company_id, code, method, impair_date, basis, amount, details, warnings, entry_id)
  values (v_company, v_code, 'global', v_date, v_basis, v_amt, v_details, v_warn, v_entry)
  returning id into v_id;
  v_no := erp.adjust_finish(v_entry);
  impairment_id := v_id; code := v_code; entry_no := v_no; amount := v_amt; warnings := v_warn;
  return next;
end $$;

-- ---------------------------------------------------------------------
-- 7) Revertir un deterioro (cobro del cliente o nueva estimación): 490 D / 794 H
-- ---------------------------------------------------------------------
create or replace function erp.reverse_impairment(p_impairment uuid, p_date date)
returns int language plpgsql security definer set search_path = erp, public as $$
declare i erp.receivable_impairments; v_entry uuid; v_no int;
begin
  select * into i from erp.receivable_impairments where id = p_impairment;
  if not found then raise exception 'Impairment not found'; end if;
  if not erp.can_write(i.company_id) then raise exception 'No permission to register impairments in this company'; end if;
  if i.status <> 'active' then raise exception 'Impairment % is not active', i.code; end if;
  if p_date is null or p_date < i.impair_date then raise exception 'The reversal date cannot be earlier than the impairment (%)', i.impair_date; end if;
  v_entry := erp.adjust_post(i.company_id, p_date, 'Reversión del deterioro ' || i.code, null,
    erp.adjust_account(i.company_id, '490', 'Deterioro de valor de créditos por operaciones comerciales'),
    erp.adjust_account(i.company_id, '794', 'Reversión del deterioro de créditos por operaciones comerciales'), i.amount);
  update erp.receivable_impairments set status = 'reversed', end_date = p_date, end_entry_id = v_entry where id = i.id;
  v_no := erp.adjust_finish(v_entry);
  return v_no;
end $$;

-- ---------------------------------------------------------------------
-- 8) Insolvencia firme de una factura: 650 D / 430 H por lo pendiente (cierra la partida como un cobro sin banco)
--    y, si tenía deterioro individual, 490 D / 794 H por ese deterioro.
--   p: { invoice_id, writeoff_date, description }  →  { writeoff_id, entry_no, amount, impairment_applied }
-- ---------------------------------------------------------------------
create or replace function erp.write_off_receivable(p jsonb)
returns table (writeoff_id uuid, entry_no int, amount numeric, impairment_applied numeric)
language plpgsql security definer set search_path = erp, public as $$
declare
  v_inv     erp.invoices;
  v_date    date := (p->>'writeoff_date')::date;
  v_partner erp.business_partners;
  v_oi      record;
  v_imp     erp.receivable_impairments;
  v_loss    uuid;
  v_entry   uuid;
  v_pay     uuid;
  v_id      uuid;
  v_no      int;
  v_desc    text;
begin
  select * into v_inv from erp.invoices where id = (p->>'invoice_id')::uuid;
  if not found then raise exception 'Invoice not found'; end if;
  if not erp.can_write(v_inv.company_id) then raise exception 'No permission to register impairments in this company'; end if;
  if v_inv.invoice_type <> 'sale' or v_inv.document_kind <> 'invoice' then raise exception 'Only issued invoices can be written off'; end if;
  if v_date is null then raise exception 'The write-off date is required'; end if;
  select * into v_oi from erp.open_items(v_inv.company_id, v_date) o where o.invoice_id = v_inv.id;
  if v_oi is null or v_oi.pending <= 0 then raise exception 'Invoice % has nothing pending at %', v_inv.invoice_no, v_date; end if;
  select * into v_partner from erp.business_partners where id = v_inv.partner_id;
  if v_partner.gl_account_id is null then raise exception 'Partner % has no posting account', v_partner.name; end if;
  select * into v_imp from erp.receivable_impairments i where i.invoice_id = v_inv.id and i.status = 'active';
  if v_imp.id is not null and v_imp.impair_date > v_date then
    raise exception 'The write-off cannot be earlier than the impairment (%)', v_imp.impair_date;
  end if;

  v_desc := coalesce(nullif(btrim(p->>'description'), ''), 'Insolvencia firme · factura ' || v_inv.invoice_no || ' · ' || v_partner.name);
  v_loss := erp.adjust_account(v_inv.company_id, '650', 'Pérdidas de créditos comerciales incobrables');
  v_entry := erp.adjust_post(v_inv.company_id, v_date, v_desc, v_inv.invoice_no, v_loss, v_partner.gl_account_id, v_oi.pending, v_partner.id);
  if v_imp.id is not null then
    insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description) values
      (v_entry, v_inv.company_id, 3, erp.adjust_account(v_inv.company_id, '490', 'Deterioro de valor de créditos por operaciones comerciales'),
       v_imp.amount, 0, 'Aplicación del deterioro ' || v_imp.code),
      (v_entry, v_inv.company_id, 4, erp.adjust_account(v_inv.company_id, '794', 'Reversión del deterioro de créditos por operaciones comerciales'),
       0, v_imp.amount, 'Aplicación del deterioro ' || v_imp.code);
  end if;

  -- La partida abierta se cierra como un cobro (sin banco: la «contrapartida» es la 650)
  insert into erp.payments (company_id, payment_type, partner_id, payment_date, cash_account_id, amount, description, entry_id)
  values (v_inv.company_id, 'collection', v_partner.id, v_date, v_loss, v_oi.pending, v_desc, v_entry)
  returning id into v_pay;
  insert into erp.payment_applications (payment_id, invoice_id, company_id, amount)
  values (v_pay, v_inv.id, v_inv.company_id, v_oi.pending);
  insert into erp.receivable_writeoffs (company_id, invoice_id, partner_id, writeoff_date, amount, impairment_id, impairment_applied, entry_id, payment_id)
  values (v_inv.company_id, v_inv.id, v_partner.id, v_date, v_oi.pending, v_imp.id, coalesce(v_imp.amount, 0), v_entry, v_pay)
  returning id into v_id;
  if v_imp.id is not null then
    update erp.receivable_impairments set status = 'written_off', end_date = v_date, end_entry_id = v_entry where id = v_imp.id;
  end if;
  v_no := erp.adjust_finish(v_entry);
  writeoff_id := v_id; entry_no := v_no; amount := v_oi.pending; impairment_applied := coalesce(v_imp.amount, 0);
  return next;
end $$;

-- Deshacer una insolvencia: contraasiento; la factura vuelve a estar pendiente y su deterioro, activo
create or replace function erp.cancel_write_off(p_writeoff uuid, p_date date default null)
returns int language plpgsql security definer set search_path = erp, public as $$
declare w erp.receivable_writeoffs; v_no int; v_rev uuid;
begin
  select * into w from erp.receivable_writeoffs where id = p_writeoff;
  if not found then raise exception 'Write-off not found'; end if;
  if not erp.can_write(w.company_id) then raise exception 'No permission to register impairments in this company'; end if;
  if w.cancel_entry_id is not null then raise exception 'This write-off is already cancelled'; end if;
  v_no := erp.adjust_reverse(w.entry_id, coalesce(p_date, w.writeoff_date), 'Insolvencia anulada');
  v_rev := (select reversed_by from erp.journal_entries where id = w.entry_id);
  update erp.payments set cancel_entry_id = v_rev where id = w.payment_id;
  update erp.receivable_writeoffs set cancel_entry_id = v_rev where id = w.id;
  if w.impairment_id is not null then
    update erp.receivable_impairments set status = 'active', end_date = null, end_entry_id = null where id = w.impairment_id;
  end if;
  return v_no;
end $$;

-- Deshacer el último paso de un deterioro: su reversión, si la hay; si no, el deterioro (contraasiento)
create or replace function erp.cancel_impairment(p_impairment uuid, p_date date default null)
returns int language plpgsql security definer set search_path = erp, public as $$
declare i erp.receivable_impairments; v_no int;
begin
  select * into i from erp.receivable_impairments where id = p_impairment;
  if not found then raise exception 'Impairment not found'; end if;
  if not erp.can_write(i.company_id) then raise exception 'No permission to register impairments in this company'; end if;
  if i.status = 'cancelled' then raise exception 'Impairment % is already cancelled', i.code; end if;
  if i.status = 'written_off' then raise exception 'Impairment % was applied to a write-off: cancel the write-off first', i.code; end if;
  if i.status = 'reversed' then
    if exists (select 1 from erp.receivable_impairments x where x.invoice_id = i.invoice_id and x.status = 'active' and x.id <> i.id)
       or (i.method = 'global' and exists (select 1 from erp.receivable_impairments x
                                           where x.company_id = i.company_id and x.method = 'global' and x.status = 'active')) then
      raise exception 'There is a newer active impairment: cancel it first';
    end if;
    v_no := erp.adjust_reverse(i.end_entry_id, coalesce(p_date, i.end_date), 'Reversión deshecha');
    update erp.receivable_impairments set status = 'active', end_date = null, end_entry_id = null where id = i.id;
  else
    v_no := erp.adjust_reverse(i.entry_id, coalesce(p_date, i.impair_date), 'Deterioro anulado');
    update erp.receivable_impairments set status = 'cancelled', cancel_entry_id = (select reversed_by from erp.journal_entries where id = i.entry_id)
    where id = i.id;
  end if;
  return v_no;
end $$;

-- ---------------------------------------------------------------------
-- 9) Los asientos de estos módulos no se anulan sueltos desde el diario (ni desde Cobros y pagos)
-- ---------------------------------------------------------------------
create or replace function erp.tg_entry_adjust_reverse()
returns trigger language plpgsql as $$
begin
  if new.reversal_of is not null and coalesce(current_setting('erp.adjust_engine', true), '') <> 'on' then
    if exists (select 1 from erp.accruals where new.reversal_of in (entry_id, reversal_entry_id)) then
      raise exception 'This entry belongs to an accrual: undo it from Year-end adjustments';
    end if;
    if exists (select 1 from erp.receivable_impairments where new.reversal_of in (entry_id, end_entry_id))
       or exists (select 1 from erp.receivable_writeoffs where entry_id = new.reversal_of) then
      raise exception 'This entry belongs to a receivable impairment: undo it from Year-end adjustments';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists entry_adjust_reverse on erp.journal_entries;
create trigger entry_adjust_reverse before insert on erp.journal_entries
  for each row execute function erp.tg_entry_adjust_reverse();

-- ---------------------------------------------------------------------
-- 10) Cuentas controladas (0036): 480 / 485 / 4009 / 4309 por Periodificaciones, 490 por Deterioro
-- ---------------------------------------------------------------------
insert into erp.control_rules (account_prefix, modules, side, note, note_en) values
('480',  '{accruals}',    'both', 'Gastos anticipados: los mueve la periodificación del cierre y su reversión.', 'Prepaid expenses: posted by the year-end accrual and its reversal.'),
('485',  '{accruals}',    'both', 'Ingresos anticipados: los mueve la periodificación del cierre y su reversión.', 'Deferred income: posted by the year-end accrual and its reversal.'),
('4009', '{accruals}',    'both', 'Facturas pendientes de recibir: las mueve la periodificación del cierre y su reversión.', 'Invoices pending receipt: posted by the year-end accrual and its reversal.'),
('4309', '{accruals}',    'both', 'Facturas pendientes de formalizar: las mueve la periodificación del cierre y su reversión.', 'Invoices pending issue: posted by the year-end accrual and its reversal.'),
('490',  '{impairments}', 'both', 'Deterioro de clientes: lo mueven el deterioro, su reversión y la insolvencia firme.', 'Impairment of receivables: posted by the impairment, its reversal and the write-off.')
on conflict (account_prefix) do update set modules = excluded.modules, side = excluded.side, note = excluded.note, note_en = excluded.note_en;

-- ---------------------------------------------------------------------
-- 11) Versiones nuevas de funciones existentes (copiadas de la vigente; cambia solo lo marcado «v0.36.0»)
-- ---------------------------------------------------------------------
create or replace function erp.entry_is_manual(p_entry uuid)
returns boolean language sql stable security definer set search_path = erp, public as $$
  select e.entry_type = 'normal' and e.reversal_of is null and e.reversed_by is null and e.import_batch_id is null
     and not exists (select 1 from erp.invoices i where i.entry_id = e.id)
     and not exists (select 1 from erp.tax_settlements s where s.entry_id = e.id)
     and not exists (select 1 from erp.pro_rata p where p.entry_id = e.id)
     and not exists (select 1 from erp.year_closings c where e.id in (c.closing_pl_entry_id, c.closing_entry_id, c.opening_entry_id))
     and not exists (select 1 from erp.payments py where py.entry_id = e.id and not py.linked)
     and not exists (select 1 from erp.asset_depreciations d where d.entry_id = e.id)
     and not exists (select 1 from erp.fixed_assets fa where fa.disposal_entry_id = e.id)
     -- v0.36.0: periodificaciones y deterioros
     and not exists (select 1 from erp.accruals ac where e.id in (ac.entry_id, ac.reversal_entry_id))
     and not exists (select 1 from erp.receivable_impairments ri where e.id in (ri.entry_id, ri.end_entry_id))
  from erp.journal_entries e where e.id = p_entry;
$$;

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
            when exists (select 1 from erp.payments py where not py.linked and (py.entry_id = e.id or py.cancel_entry_id = e.id)) then 'payment'
            when exists (select 1 from erp.asset_depreciations d where d.entry_id = coalesce(e.reversal_of, e.id))
              or exists (select 1 from erp.fixed_assets fa where fa.disposal_entry_id = coalesce(e.reversal_of, e.id)) then 'asset'
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
              when exists (select 1 from erp.payments py where not py.linked
                           and coalesce(e.reversal_of, e.id) in (py.entry_id, py.cancel_entry_id)) then 'payment'
              when exists (select 1 from erp.asset_depreciations d where d.entry_id = coalesce(e.reversal_of, e.id))
                or exists (select 1 from erp.fixed_assets fa where fa.disposal_entry_id = coalesce(e.reversal_of, e.id)) then 'asset'
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
$function$;

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
end $function$;

-- ---------------------------------------------------------------------
-- 12) Listas para la web
-- ---------------------------------------------------------------------
create or replace view erp.v_accruals with (security_invoker = true) as
select a.id, a.company_id, a.code, a.kind, a.description, a.cutoff_date, a.amount, a.total_amount, a.coverage_start,
       a.coverage_months, a.status, a.reversal_date,
       pl.account_no as pl_account_no, pl.name as pl_account_name, bal.account_no as balance_account_no,
       i.invoice_no, coalesce(i.external_document_no, i.invoice_no) as invoice_ref,
       e.entry_no, fy.year as fiscal_year, re.entry_no as reversal_entry_no, rfy.year as reversal_year
from erp.accruals a
join erp.gl_accounts pl on pl.id = a.pl_account_id
join erp.gl_accounts bal on bal.id = a.balance_account_id
left join erp.invoices i on i.id = a.invoice_id
join erp.journal_entries e on e.id = a.entry_id
join erp.fiscal_years fy on fy.id = e.fiscal_year_id
left join erp.journal_entries re on re.id = a.reversal_entry_id
left join erp.fiscal_years rfy on rfy.id = re.fiscal_year_id;

create or replace view erp.v_receivable_impairments with (security_invoker = true) as
select r.id, r.company_id, r.code, r.method, r.invoice_id, i.invoice_no, r.partner_id, bp.name as partner_name,
       r.impair_date, r.basis, r.pct, r.amount, r.details, r.warnings, r.status, r.end_date,
       e.entry_no, fy.year as fiscal_year, ee.entry_no as end_entry_no, efy.year as end_year
from erp.receivable_impairments r
left join erp.invoices i on i.id = r.invoice_id
left join erp.business_partners bp on bp.id = r.partner_id
join erp.journal_entries e on e.id = r.entry_id
join erp.fiscal_years fy on fy.id = e.fiscal_year_id
left join erp.journal_entries ee on ee.id = r.end_entry_id
left join erp.fiscal_years efy on efy.id = ee.fiscal_year_id;

create or replace view erp.v_receivable_writeoffs with (security_invoker = true) as
select w.id, w.company_id, w.invoice_id, i.invoice_no, w.partner_id, bp.name as partner_name, w.writeoff_date, w.amount,
       w.impairment_applied, ri.code as impairment_code, e.entry_no, fy.year as fiscal_year,
       ce.entry_no as cancel_entry_no, (w.cancel_entry_id is not null) as cancelled
from erp.receivable_writeoffs w
join erp.invoices i on i.id = w.invoice_id
join erp.business_partners bp on bp.id = w.partner_id
left join erp.receivable_impairments ri on ri.id = w.impairment_id
join erp.journal_entries e on e.id = w.entry_id
join erp.fiscal_years fy on fy.id = e.fiscal_year_id
left join erp.journal_entries ce on ce.id = w.cancel_entry_id;

revoke all on erp.v_accruals, erp.v_receivable_impairments, erp.v_receivable_writeoffs from anon, public;
grant select on erp.v_accruals, erp.v_receivable_impairments, erp.v_receivable_writeoffs to authenticated;

-- ---------------------------------------------------------------------
-- Permisos: solo las funciones públicas del módulo (las ayudas, no)
-- ---------------------------------------------------------------------
revoke execute on function erp.adjust_account(uuid, text, text), erp.adjust_fiscal_year(uuid, date),
  erp.adjust_post(uuid, date, text, text, uuid, uuid, numeric, uuid), erp.adjust_finish(uuid), erp.adjust_reverse(uuid, date, text)
  from anon, public, authenticated;
revoke execute on function erp.accrual_elapsed(numeric, date, int, date), erp.create_accrual(jsonb), erp.reverse_accrual(uuid, date),
  erp.reverse_accruals(uuid, date), erp.cancel_accrual(uuid, date), erp.impair_receivable(jsonb),
  erp.global_impairment_calc(uuid, date, jsonb), erp.impair_receivables_global(jsonb), erp.reverse_impairment(uuid, date),
  erp.write_off_receivable(jsonb), erp.cancel_write_off(uuid, date), erp.cancel_impairment(uuid, date)
  from anon, public;
grant execute on function erp.accrual_elapsed(numeric, date, int, date), erp.create_accrual(jsonb), erp.reverse_accrual(uuid, date),
  erp.reverse_accruals(uuid, date), erp.cancel_accrual(uuid, date), erp.impair_receivable(jsonb),
  erp.global_impairment_calc(uuid, date, jsonb), erp.impair_receivables_global(jsonb), erp.reverse_impairment(uuid, date),
  erp.write_off_receivable(jsonb), erp.cancel_write_off(uuid, date), erp.cancel_impairment(uuid, date)
  to authenticated;
