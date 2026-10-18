-- =====================================================================
-- 0049 · NÓMINAS: empleados, cotizaciones, asiento de la nómina, pagas extra y pagos · v0.38.0
-- ---------------------------------------------------------------------
-- La nómina mensual de una pyme con su asiento del PGC (como el módulo de RR. HH. de Business Central o HCM de SAP,
-- pero para aprender el asiento, no para sustituir a un programa de nóminas):
--   · base de cotización = salario del mes + PRORRATA de las pagas extra (art. 147 LGSS), con el tope máximo del año;
--   · cuotas: tabla de TIPOS del año (Orden PJC/297/2026 para 2026) + el tipo de AT / EP del puesto (tarifa de primas,
--     DA 4.ª Ley 42/2006) + la cotización adicional de solidaridad sobre lo que supera la base máxima;
--   · IRPF: el % del empleado (el que da el algoritmo de la AEAT; el ERP no lo calcula) sobre lo que se paga ese mes;
--   · pagas extra NO prorrateadas: cada mes se devenga su parte (640 D / 465 H) y en junio y diciembre se paga lo devengado.
--   Asiento:  640 D salario (+ paga extra devengada) · 642 D Seguridad Social a cargo de la empresa
--             476 H cuotas (empresa + trabajador) · 4751 H IRPF · 465 H líquido a pagar (+ paga devengada)
--             (y en el mes de paga: 465 D la paga devengada que se paga ese mes)
--   Pago del líquido: 465 D / 57x H · pago de los seguros sociales (mes siguiente): 476 D / 57x H.
-- No incluye: bases mínimas por grupo de cotización, IT, horas extra, embargos (decidido el 18-10-2026). Re-ejecutable.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Tipos de cotización del año (Régimen General)
-- ---------------------------------------------------------------------
create table if not exists erp.ss_rates (
  year          int not null,
  concept       text not null,     -- common · unemployment_indefinite · unemployment_temporary · fogasa · training · mei · solidarity_1..3
  sort          int not null,
  name          text not null,
  name_en       text not null,
  employer_pct  numeric(6,3) not null,
  employee_pct  numeric(6,3) not null,
  primary key (year, concept)
);
create table if not exists erp.ss_limits (
  year           int primary key,
  max_base       numeric(15,2) not null,     -- base máxima mensual
  min_base       numeric(15,2) not null,     -- base mínima más baja (grupos 4 a 11): solo para avisar
  solidarity_1   numeric(15,2) not null,     -- tramos de la cotización de solidaridad: hasta max × 1,10 / × 1,50 / más
  solidarity_2   numeric(15,2) not null,
  legal_reference text not null
);
insert into erp.ss_rates (year, concept, sort, name, name_en, employer_pct, employee_pct) values
(2026, 'common',                  10, 'Contingencias comunes', 'Common contingencies', 23.60, 4.70),
(2026, 'unemployment_indefinite', 20, 'Desempleo (contrato indefinido)', 'Unemployment (permanent contract)', 5.50, 1.55),
(2026, 'unemployment_temporary',  21, 'Desempleo (contrato temporal)', 'Unemployment (temporary contract)', 6.70, 1.60),
(2026, 'fogasa',                  30, 'FOGASA', 'Wage guarantee fund (FOGASA)', 0.20, 0),
(2026, 'training',                40, 'Formación profesional', 'Vocational training', 0.60, 0.10),
(2026, 'mei',                     50, 'Mecanismo de Equidad Intergeneracional (MEI)', 'Intergenerational equity mechanism (MEI)', 0.75, 0.15),
(2026, 'solidarity_1',            60, 'Solidaridad (hasta +10 % de la base máxima)', 'Solidarity (up to +10 % of the maximum base)', 0.96, 0.19),
(2026, 'solidarity_2',            61, 'Solidaridad (+10 % a +50 %)', 'Solidarity (+10 % to +50 %)', 1.04, 0.21),
(2026, 'solidarity_3',            62, 'Solidaridad (más de +50 %)', 'Solidarity (over +50 %)', 1.22, 0.24)
on conflict (year, concept) do update set sort = excluded.sort, name = excluded.name, name_en = excluded.name_en,
  employer_pct = excluded.employer_pct, employee_pct = excluded.employee_pct;
insert into erp.ss_limits (year, max_base, min_base, solidarity_1, solidarity_2, legal_reference) values
(2026, 5101.20, 1424.40, 5611.32, 7651.80, 'Orden PJC/297/2026, de 30 de marzo (BOE 31/03/2026), con efectos desde el 1 de enero de 2026')
on conflict (year) do update set max_base = excluded.max_base, min_base = excluded.min_base,
  solidarity_1 = excluded.solidarity_1, solidarity_2 = excluded.solidarity_2, legal_reference = excluded.legal_reference;
alter table erp.ss_rates enable row level security;
alter table erp.ss_limits enable row level security;
drop policy if exists read on erp.ss_rates;
drop policy if exists read on erp.ss_limits;
create policy read on erp.ss_rates for select to authenticated using (true);
create policy read on erp.ss_limits for select to authenticated using (true);
revoke all on erp.ss_rates, erp.ss_limits from anon, public;
grant select on erp.ss_rates, erp.ss_limits to authenticated;

-- ---------------------------------------------------------------------
-- 2) Empleados (ficticios: nombre y datos de la nómina, sin IBAN ni datos personales)
-- ---------------------------------------------------------------------
create table if not exists erp.employees (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null references erp.companies(id) on delete cascade,
  code            text not null,
  name            text not null,
  contract_type   text not null default 'indefinite' check (contract_type in ('indefinite', 'temporary')),
  hire_date       date not null,
  end_date        date,
  monthly_salary  numeric(15,2) not null check (monthly_salary > 0),   -- salario base + complementos fijos del mes
  extra_payments  int not null default 2 check (extra_payments between 0 and 4),
  extra_prorated  boolean not null default false,                       -- pagas extra prorrateadas en cada nómina
  irpf_pct        numeric(5,2) not null default 0 check (irpf_pct between 0 and 47),
  at_ep_pct       numeric(5,2) not null default 1.00 check (at_ep_pct between 0 and 10),   -- 1,00 = cuadro II «a» (oficina)
  created_at      timestamptz not null default now(),
  unique (company_id, code),
  check (end_date is null or end_date >= hire_date)
);
comment on table erp.employees is 'Employees (fictitious, for learning the payroll entry): salary, extra payments, IRPF % and AT/EP rate.';
create index if not exists employees_company_idx on erp.employees (company_id);

-- Nómina del mes (una por empresa y mes) y la de cada empleado
create table if not exists erp.payroll_runs (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null references erp.companies(id) on delete cascade,
  period           date not null,                -- último día del mes
  entry_id         uuid not null references erp.journal_entries(id),
  status           text not null default 'posted' check (status in ('posted', 'cancelled')),
  cancel_entry_id  uuid references erp.journal_entries(id),
  net_payment_entry_id uuid references erp.journal_entries(id),
  ss_payment_entry_id  uuid references erp.journal_entries(id),
  created_at       timestamptz not null default now()
);
create unique index if not exists payroll_runs_one_per_month on erp.payroll_runs (company_id, period) where status = 'posted';
create index if not exists payroll_runs_entry_idx  on erp.payroll_runs (entry_id);
create index if not exists payroll_runs_cancel_idx on erp.payroll_runs (cancel_entry_id);
create index if not exists payroll_runs_net_idx    on erp.payroll_runs (net_payment_entry_id);
create index if not exists payroll_runs_ss_idx     on erp.payroll_runs (ss_payment_entry_id);

create table if not exists erp.payslips (
  run_id          uuid not null references erp.payroll_runs(id) on delete cascade,
  employee_id     uuid not null references erp.employees(id),
  company_id      uuid not null references erp.companies(id) on delete cascade,
  salary          numeric(15,2) not null,   -- devengos del mes que se pagan (salario, + prorrata si va prorrateada)
  extra_accrual   numeric(15,2) not null,   -- paga extra devengada este mes (no prorrateada) → 465
  extra_paid      numeric(15,2) not null,   -- paga extra que se paga este mes (lo devengado)
  ss_base         numeric(15,2) not null,   -- base de cotización (con la prorrata y el tope)
  ss_employee     numeric(15,2) not null,
  ss_employer     numeric(15,2) not null,
  ss_detail       jsonb not null,           -- [{ concept, name, base, employer_pct, employee_pct, employer, employee }]
  irpf_pct        numeric(5,2) not null,
  irpf            numeric(15,2) not null,
  net             numeric(15,2) not null,   -- líquido a percibir
  warnings        jsonb not null default '[]',
  primary key (run_id, employee_id)
);
create index if not exists payslips_company_idx  on erp.payslips (company_id);
create index if not exists payslips_employee_idx on erp.payslips (employee_id);

alter table erp.employees enable row level security;
alter table erp.payroll_runs enable row level security;
alter table erp.payslips enable row level security;
drop policy if exists read on erp.employees;
drop policy if exists read on erp.payroll_runs;
drop policy if exists read on erp.payslips;
create policy read on erp.employees for select to authenticated using (erp.can_read(company_id));
create policy read on erp.payroll_runs for select to authenticated using (erp.can_read(company_id));
create policy read on erp.payslips for select to authenticated using (erp.can_read(company_id));
revoke all on erp.employees, erp.payroll_runs, erp.payslips from anon, public;
grant select on erp.employees, erp.payroll_runs, erp.payslips to authenticated;

-- ---------------------------------------------------------------------
-- 3) Alta y cambios del empleado
--   p: { company_id, name, contract_type, hire_date, monthly_salary, extra_payments, extra_prorated, irpf_pct, at_ep_pct }
-- ---------------------------------------------------------------------
create or replace function erp.save_employee(p jsonb)
returns uuid language plpgsql security definer set search_path = erp, public as $$
declare v_company uuid := (p->>'company_id')::uuid; v_id uuid := (p->>'id')::uuid; v_code text;
begin
  if not erp.can_write(v_company) then raise exception 'No permission to register payroll in this company'; end if;
  if coalesce(btrim(p->>'name'), '') = '' then raise exception 'The employee needs a name'; end if;
  if (p->>'hire_date') is null then raise exception 'The hire date is required'; end if;
  if coalesce((p->>'monthly_salary')::numeric, 0) <= 0 then raise exception 'The monthly salary must be greater than zero'; end if;
  if v_id is null then
    select 'EMP-' || lpad((count(*) + 1)::text, 4, '0') into v_code from erp.employees where company_id = v_company;
    insert into erp.employees (company_id, code, name, contract_type, hire_date, end_date, monthly_salary, extra_payments, extra_prorated, irpf_pct, at_ep_pct)
    values (v_company, v_code, btrim(p->>'name'), coalesce(p->>'contract_type', 'indefinite'), (p->>'hire_date')::date, (p->>'end_date')::date,
            round((p->>'monthly_salary')::numeric, 2), coalesce((p->>'extra_payments')::int, 2), coalesce((p->>'extra_prorated')::boolean, false),
            coalesce((p->>'irpf_pct')::numeric, 0), coalesce((p->>'at_ep_pct')::numeric, 1.00))
    returning id into v_id;
  else
    update erp.employees set name = btrim(p->>'name'), contract_type = coalesce(p->>'contract_type', contract_type),
      end_date = (p->>'end_date')::date, monthly_salary = round((p->>'monthly_salary')::numeric, 2),
      extra_payments = coalesce((p->>'extra_payments')::int, extra_payments), extra_prorated = coalesce((p->>'extra_prorated')::boolean, extra_prorated),
      irpf_pct = coalesce((p->>'irpf_pct')::numeric, irpf_pct), at_ep_pct = coalesce((p->>'at_ep_pct')::numeric, at_ep_pct)
    where id = v_id and company_id = v_company;
    if not found then raise exception 'Employee not found'; end if;
  end if;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- 4) Cálculo de la nómina de un empleado en un mes (no contabiliza): erp.payslip_calc(empleado, último día del mes)
-- ---------------------------------------------------------------------
create or replace function erp.payslip_calc(p_employee uuid, p_period date)
returns jsonb language plpgsql stable as $$
declare
  e        erp.employees;
  lim      erp.ss_limits;
  r        record;
  v_year   int := extract(year from p_period)::int;
  v_month  int := extract(month from p_period)::int;
  v_prorr  numeric;     -- prorrata mensual de las pagas extra
  v_salary numeric;     -- lo que se paga este mes por salario
  v_base   numeric;     -- base de cotización
  v_rem    numeric;     -- remuneración total del mes (para la solidaridad)
  v_acc    numeric := 0;
  v_paid   numeric := 0;
  v_prev   numeric;     -- lo devengado de la paga desde el último pago
  v_n      int;         -- meses del periodo de devengo de esta paga
  v_ee     numeric := 0; v_er numeric := 0; v_det jsonb := '[]'; v_amt_e numeric; v_amt_r numeric; v_b numeric;
  v_irpf   numeric;
  v_warn   jsonb := '[]';
  v_pay_month boolean;
begin
  select * into e from erp.employees where id = p_employee;
  select * into lim from erp.ss_limits where year = v_year;
  if lim.year is null then raise exception 'There are no contribution rates for %: they are published each year (Orden de cotización)', v_year; end if;

  v_prorr := round(e.monthly_salary * e.extra_payments / 12, 2);
  -- meses de pago de las pagas extra: junio y diciembre (2), o repartidos si son más (3: abril, agosto y diciembre…)
  v_pay_month := e.extra_payments > 0 and v_month % (12 / greatest(e.extra_payments, 1)) = 0;
  if e.extra_prorated then
    v_salary := e.monthly_salary + v_prorr;
  else
    v_salary := e.monthly_salary;
    if e.extra_payments > 0 then
      -- lo devengado desde el último mes de paga (en las nóminas ya contabilizadas)
      select coalesce(sum(s.extra_accrual), 0), count(*) into v_prev, v_n
      from erp.payslips s join erp.payroll_runs pr on pr.id = s.run_id
      where s.employee_id = e.id and pr.status = 'posted' and pr.period < p_period
        and pr.period > (select coalesce(max(pr2.period), '1900-01-01') from erp.payslips s2 join erp.payroll_runs pr2 on pr2.id = s2.run_id
                         where s2.employee_id = e.id and pr2.status = 'posted' and pr2.period < p_period and s2.extra_paid > 0);
      v_acc := v_prorr;
      if v_pay_month then
        -- el mes de paga cuadra el redondeo: la paga es exactamente la parte de los meses devengados
        v_acc := round(e.monthly_salary * e.extra_payments / 12 * (v_n + 1), 2) - v_prev;
        v_paid := v_prev + v_acc;
      end if;
    end if;
  end if;

  -- Base de cotización: salario + prorrata de las pagas extra, con el tope máximo
  v_rem := e.monthly_salary + v_prorr;
  v_base := least(v_rem, lim.max_base);
  if e.hire_date > date_trunc('month', p_period)::date or (e.end_date is not null and e.end_date < p_period) then
    v_warn := v_warn || jsonb_build_object('code', 'partial_month');   -- el ERP liquida el mes entero: prorratea a mano
  end if;
  if v_base < lim.min_base then v_warn := v_warn || jsonb_build_object('code', 'below_min_base', 'min_base', lim.min_base); end if;

  for r in select * from erp.ss_rates s where s.year = v_year
           and s.concept <> case e.contract_type when 'indefinite' then 'unemployment_temporary' else 'unemployment_indefinite' end
           order by s.sort loop
    v_b := case r.concept
      when 'solidarity_1' then greatest(least(v_rem, lim.solidarity_1) - lim.max_base, 0)
      when 'solidarity_2' then greatest(least(v_rem, lim.solidarity_2) - lim.solidarity_1, 0)
      when 'solidarity_3' then greatest(v_rem - lim.solidarity_2, 0)
      else v_base end;
    if v_b = 0 then continue; end if;
    v_amt_r := round(v_b * r.employer_pct / 100, 2); v_amt_e := round(v_b * r.employee_pct / 100, 2);
    v_er := v_er + v_amt_r; v_ee := v_ee + v_amt_e;
    v_det := v_det || jsonb_build_object('concept', r.concept, 'name', r.name, 'name_en', r.name_en, 'base', v_b,
                                         'employer_pct', r.employer_pct, 'employee_pct', r.employee_pct, 'employer', v_amt_r, 'employee', v_amt_e);
  end loop;
  -- AT / EP: solo la empresa (tarifa de primas)
  v_amt_r := round(v_base * e.at_ep_pct / 100, 2); v_er := v_er + v_amt_r;
  v_det := v_det || jsonb_build_object('concept', 'at_ep', 'name', 'Accidentes de trabajo y enfermedades profesionales', 'name_en', 'Work accidents and occupational diseases',
                                       'base', v_base, 'employer_pct', e.at_ep_pct, 'employee_pct', 0, 'employer', v_amt_r, 'employee', 0);

  v_irpf := round((v_salary + v_paid) * e.irpf_pct / 100, 2);
  return jsonb_build_object('salary', v_salary, 'extra_accrual', v_acc, 'extra_paid', v_paid, 'ss_base', v_base,
    'ss_employee', v_ee, 'ss_employer', v_er, 'ss_detail', v_det, 'irpf_pct', e.irpf_pct, 'irpf', v_irpf,
    'net', v_salary + v_paid - v_irpf - v_ee, 'warnings', v_warn);
end $$;

-- ---------------------------------------------------------------------
-- 5) Contabilizar la nómina del mes (todos los empleados en alta ese mes)
--   p: { company_id, period (último día del mes) }
-- ---------------------------------------------------------------------
create or replace function erp.run_payroll(p jsonb)
returns table (run_id uuid, entry_no int, employees int, gross numeric, net numeric)
language plpgsql security definer set search_path = erp, public as $$
declare
  v_company uuid := (p->>'company_id')::uuid;
  v_period  date := (date_trunc('month', (p->>'period')::date) + interval '1 month - 1 day')::date;
  v_entry   uuid; v_run uuid; e erp.employees; c jsonb; v_n int := 0; v_line int := 0; v_gross numeric := 0; v_net numeric := 0;
  a640 uuid; a642 uuid; a476 uuid; a4751 uuid; a465 uuid; v_no int;
begin
  if not erp.can_write(v_company) then raise exception 'No permission to register payroll in this company'; end if;
  if (p->>'period') is null then raise exception 'The month is required'; end if;
  if exists (select 1 from erp.payroll_runs r where r.company_id = v_company and r.period = v_period and r.status = 'posted') then
    raise exception 'The payroll of % is already posted', to_char(v_period, 'MM/YYYY');
  end if;
  if exists (select 1 from erp.payroll_runs r where r.company_id = v_company and r.period > v_period and r.status = 'posted') then
    raise exception 'There is a later payroll: post the months in order';
  end if;
  a640 := erp.adjust_account(v_company, '640', 'Sueldos y salarios');
  a642 := erp.adjust_account(v_company, '642', 'Seguridad Social a cargo de la empresa');
  a476 := erp.adjust_account(v_company, '476', 'Organismos de la Seguridad Social, acreedores');
  a4751 := erp.adjust_account(v_company, '4751', 'Hacienda Pública, acreedora por retenciones practicadas');
  a465 := erp.adjust_account(v_company, '465', 'Remuneraciones pendientes de pago');
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (v_company, erp.adjust_fiscal_year(v_company, v_period), v_period, 'Nómina de ' || to_char(v_period, 'MM/YYYY'))
  returning id into v_entry;
  insert into erp.payroll_runs (company_id, period, entry_id) values (v_company, v_period, v_entry) returning id into v_run;

  for e in select * from erp.employees x where x.company_id = v_company and x.hire_date <= v_period
           and (x.end_date is null or x.end_date >= date_trunc('month', v_period)) order by x.code loop
    c := erp.payslip_calc(e.id, v_period);
    insert into erp.payslips (run_id, employee_id, company_id, salary, extra_accrual, extra_paid, ss_base, ss_employee, ss_employer,
                              ss_detail, irpf_pct, irpf, net, warnings)
    values (v_run, e.id, v_company, (c->>'salary')::numeric, (c->>'extra_accrual')::numeric, (c->>'extra_paid')::numeric,
            (c->>'ss_base')::numeric, (c->>'ss_employee')::numeric, (c->>'ss_employer')::numeric, c->'ss_detail',
            (c->>'irpf_pct')::numeric, (c->>'irpf')::numeric, (c->>'net')::numeric, c->'warnings');
    insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description)
    select v_entry, v_company, v_line + row_number() over (), x.acc, x.d, x.h, e.code || ' · ' || e.name || ' · ' || x.txt
    from (values
      (1, a640, (c->>'salary')::numeric, 0::numeric, 'salario'),
      (2, a640, (c->>'extra_accrual')::numeric, 0::numeric, 'paga extra devengada'),
      (3, a465, (c->>'extra_paid')::numeric, 0::numeric, 'paga extra que se paga'),
      (4, a642, (c->>'ss_employer')::numeric, 0::numeric, 'Seguridad Social a cargo de la empresa'),
      (5, a476, 0::numeric, (c->>'ss_employer')::numeric + (c->>'ss_employee')::numeric, 'cuotas de la Seguridad Social'),
      (6, a4751, 0::numeric, (c->>'irpf')::numeric, 'retención del IRPF'),
      (7, a465, 0::numeric, (c->>'net')::numeric, 'líquido a pagar'),
      (8, a465, 0::numeric, (c->>'extra_accrual')::numeric, 'paga extra devengada')) as x(k, acc, d, h, txt)
    where x.d <> 0 or x.h <> 0 order by x.k;
    get diagnostics v_line = row_count;
    v_line := (select max(line_no) from erp.journal_lines where entry_id = v_entry);
    v_n := v_n + 1; v_gross := v_gross + (c->>'salary')::numeric + (c->>'extra_accrual')::numeric; v_net := v_net + (c->>'net')::numeric;
  end loop;
  if v_n = 0 then raise exception 'There are no employees in % (check the hire dates)', to_char(v_period, 'MM/YYYY'); end if;
  v_no := erp.adjust_finish(v_entry);
  run_id := v_run; entry_no := v_no; employees := v_n; gross := v_gross; net := v_net;
  return next;
end $$;

-- ---------------------------------------------------------------------
-- 6) Pagos: el líquido de la nómina (465 D / 57x H, con la paga extra si es mes de paga) y los seguros sociales
--    (476 D / 57x H, normalmente el mes siguiente)
--   p: { run_id, what: net | social_security, payment_date, cash_account_no }
-- ---------------------------------------------------------------------
create or replace function erp.pay_payroll(p jsonb)
returns int language plpgsql security definer set search_path = erp, public as $$
declare
  r erp.payroll_runs; v_date date := (p->>'payment_date')::date; v_cash erp.gl_accounts; v_amt numeric; v_entry uuid; v_no int;
  v_what text := coalesce(p->>'what', 'net');
begin
  select * into r from erp.payroll_runs where id = (p->>'run_id')::uuid;
  if not found then raise exception 'Payroll not found'; end if;
  if not erp.can_write(r.company_id) then raise exception 'No permission to register payroll in this company'; end if;
  if r.status <> 'posted' then raise exception 'This payroll is cancelled'; end if;
  if v_what not in ('net', 'social_security') then raise exception 'Invalid payment: %', v_what; end if;
  if v_date is null or v_date < r.period - 5 then raise exception 'The payment date is required (and not before the end of the month)'; end if;
  if (v_what = 'net' and r.net_payment_entry_id is not null) or (v_what = 'social_security' and r.ss_payment_entry_id is not null) then
    raise exception 'This payment is already posted';
  end if;
  select * into v_cash from erp.gl_accounts where company_id = r.company_id and account_no = p->>'cash_account_no' and account_type = 'posting';
  if not found or left(v_cash.account_no, 2) <> '57' then raise exception 'Choose a cash or bank account (57)'; end if;
  select case v_what when 'net' then sum(s.net) else sum(s.ss_employee + s.ss_employer) end into v_amt from erp.payslips s where s.run_id = r.id;
  v_entry := erp.adjust_post(r.company_id, v_date,
    case v_what when 'net' then 'Pago de la nómina de ' else 'Pago de los seguros sociales de ' end || to_char(r.period, 'MM/YYYY'), null,
    erp.adjust_account(r.company_id, case v_what when 'net' then '465' else '476' end,
                       case v_what when 'net' then 'Remuneraciones pendientes de pago' else 'Organismos de la Seguridad Social, acreedores' end),
    v_cash.id, v_amt);
  if v_what = 'net' then update erp.payroll_runs set net_payment_entry_id = v_entry where id = r.id;
  else update erp.payroll_runs set ss_payment_entry_id = v_entry where id = r.id; end if;
  v_no := erp.adjust_finish(v_entry);
  return v_no;
end $$;

-- Deshacer: el último pago hecho (primero los seguros sociales, después el líquido) o, sin pagos, la nómina entera
create or replace function erp.cancel_payroll(p_run uuid, p_date date default null)
returns int language plpgsql security definer set search_path = erp, public as $$
declare r erp.payroll_runs; v_no int;
begin
  select * into r from erp.payroll_runs where id = p_run;
  if not found then raise exception 'Payroll not found'; end if;
  if not erp.can_write(r.company_id) then raise exception 'No permission to register payroll in this company'; end if;
  if r.status <> 'posted' then raise exception 'This payroll is already cancelled'; end if;
  if r.ss_payment_entry_id is not null then
    v_no := erp.adjust_reverse(r.ss_payment_entry_id, p_date, 'Pago de seguros sociales deshecho');
    update erp.payroll_runs set ss_payment_entry_id = null where id = r.id;
  elsif r.net_payment_entry_id is not null then
    v_no := erp.adjust_reverse(r.net_payment_entry_id, p_date, 'Pago de la nómina deshecho');
    update erp.payroll_runs set net_payment_entry_id = null where id = r.id;
  else
    if exists (select 1 from erp.payroll_runs x where x.company_id = r.company_id and x.period > r.period and x.status = 'posted') then
      raise exception 'Only the last payroll can be cancelled';
    end if;
    v_no := erp.adjust_reverse(r.entry_id, coalesce(p_date, r.period), 'Nómina anulada');
    update erp.payroll_runs set status = 'cancelled', cancel_entry_id = (select reversed_by from erp.journal_entries where id = r.entry_id)
    where id = r.id;
  end if;
  return v_no;
end $$;

-- ---------------------------------------------------------------------
-- 7) Cuentas controladas: 465 y 476 por Nóminas (la 4751 la comparten nóminas y facturas: se vigila en Comprobaciones)
-- ---------------------------------------------------------------------
insert into erp.control_rules (account_prefix, modules, side, note, note_en) values
('465', '{payroll}', 'both', 'Remuneraciones pendientes de pago: las mueven la nómina y su pago.', 'Salaries payable: posted by the payroll and its payment.'),
('476', '{payroll}', 'both', 'Seguridad Social acreedora: la mueven la nómina y el pago de los seguros sociales.', 'Social Security payable: posted by the payroll and the contributions payment.')
on conflict (account_prefix) do update set modules = excluded.modules, side = excluded.side, note = excluded.note, note_en = excluded.note_en;

-- ---------------------------------------------------------------------
-- 8) Listas para la web
-- ---------------------------------------------------------------------
create or replace view erp.v_payroll_runs with (security_invoker = true) as
select r.id, r.company_id, r.period, r.status, e.entry_no, fy.year as fiscal_year,
       ne.entry_no as net_payment_entry_no, se.entry_no as ss_payment_entry_no,
       (select count(*) from erp.payslips s where s.run_id = r.id) as employees,
       (select sum(s.salary + s.extra_accrual) from erp.payslips s where s.run_id = r.id) as gross,
       (select sum(s.ss_employer) from erp.payslips s where s.run_id = r.id) as ss_employer,
       (select sum(s.ss_employee + s.ss_employer) from erp.payslips s where s.run_id = r.id) as ss_total,
       (select sum(s.irpf) from erp.payslips s where s.run_id = r.id) as irpf,
       (select sum(s.net) from erp.payslips s where s.run_id = r.id) as net,
       (select sum(s.extra_paid) from erp.payslips s where s.run_id = r.id) as extra_paid
from erp.payroll_runs r
join erp.journal_entries e on e.id = r.entry_id
join erp.fiscal_years fy on fy.id = e.fiscal_year_id
left join erp.journal_entries ne on ne.id = r.net_payment_entry_id
left join erp.journal_entries se on se.id = r.ss_payment_entry_id;
revoke all on erp.v_payroll_runs from anon, public;
grant select on erp.v_payroll_runs to authenticated;

-- ---------------------------------------------------------------------
-- 9) Versiones nuevas de funciones existentes (copiadas de la vigente, 0047; cambia solo lo marcado «v0.38.0»)
-- ---------------------------------------------------------------------
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
    -- v0.38.0: nóminas y sus pagos
    if exists (select 1 from erp.payroll_runs where new.reversal_of in (entry_id, net_payment_entry_id, ss_payment_entry_id)) then
      raise exception 'This entry belongs to a payroll: undo it from Payroll';
    end if;
  end if;
  return new;
end $function$
;
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
  from erp.journal_entries e where e.id = p_entry;
$function$
;
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
;

-- ---------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------
revoke execute on function erp.save_employee(jsonb), erp.payslip_calc(uuid, date), erp.run_payroll(jsonb), erp.pay_payroll(jsonb),
  erp.cancel_payroll(uuid, date) from anon, public;
grant execute on function erp.save_employee(jsonb), erp.payslip_calc(uuid, date), erp.run_payroll(jsonb), erp.pay_payroll(jsonb),
  erp.cancel_payroll(uuid, date) to authenticated;
