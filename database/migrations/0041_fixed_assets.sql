-- =====================================================================
-- 0041 · INMOVILIZADO: ficha del activo, amortización y baja · v0.35.0
-- ---------------------------------------------------------------------
-- Como el módulo de Activos fijos de Business Central o FI-AA de SAP, con el PGC:
--   · el activo se compra con una FACTURA RECIBIDA cuya línea va a su cuenta (20x / 21x / 22x) y se da de alta su ficha
--     (o a mano, para lo que ya existía);
--   · AMORTIZACIÓN LINEAL (NRV 2.ª y 3.ª del PGC) desde la puesta en funcionamiento: (coste − valor residual) / vida
--     útil en meses; el primer mes, proporcional a los días. Asiento: 68x Debe / 28x Haber;
--   · BAJA: amortiza hasta la fecha, cancela la 28x y lo que queda de la 2x, y lleva la diferencia a 67x (pérdida)
--     o 77x (beneficio). Si se vende, la venta es una FACTURA EMITIDA cuya línea va a la cuenta del activo (con su
--     IVA, que así entra en el libro registro y en el 303 / 420);
--   · tabla de coeficientes fiscales (art. 12.1.a de la Ley 27/2014 del Impuesto sobre Sociedades): si la amortización
--     contable supera el máximo fiscal, el ERP avisa (diferencia temporaria en el Impuesto sobre Sociedades).
--   · cuentas 20x/21x/22x y 28x CONTROLADAS por el módulo (0036): en modo estricto no se amortiza a mano.
-- Los terrenos (210, 220) no se amortizan (NRV 2.ª). Re-ejecutable.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Coeficientes fiscales (LIS art. 12.1.a, tabla de amortización): máximo % anual y período máximo en años
-- ---------------------------------------------------------------------
create table if not exists erp.depreciation_classes (
  code        text primary key,
  sort        int not null,
  pgc_prefix  text not null,          -- cuenta del PGC habitual
  name        text not null,
  name_en     text not null,
  max_pct     numeric(5,2) not null,  -- coeficiente lineal máximo
  max_years   int not null            -- período máximo
);
comment on table erp.depreciation_classes is 'Tax depreciation table (Spanish Corporate Income Tax Act, art. 12.1.a): maximum rate and period.';
insert into erp.depreciation_classes (code, sort, pgc_prefix, name, name_en, max_pct, max_years) values
('EDIF_COM',     10, '211', 'Edificios comerciales, administrativos, de servicios y viviendas', 'Commercial, office and residential buildings', 2, 100),
('EDIF_IND',     20, '211', 'Edificios industriales', 'Industrial buildings', 3, 68),
('ALMACENES',    30, '211', 'Almacenes y depósitos', 'Warehouses and depots', 7, 30),
('INSTALACIONES',40, '215', 'Otras instalaciones', 'Other installations', 10, 20),
('MAQUINARIA',   50, '213', 'Maquinaria', 'Machinery', 12, 18),
('UTILES',       60, '214', 'Útiles y herramientas', 'Tools and implements', 25, 8),
('MOLDES',       70, '214', 'Moldes, matrices y modelos', 'Moulds, dies and patterns', 33, 6),
('MOBILIARIO',   80, '216', 'Mobiliario', 'Furniture', 10, 20),
('LENCERIA',     90, '216', 'Lencería', 'Linen', 25, 8),
('CRISTALERIA', 100, '216', 'Cristalería', 'Glassware', 50, 4),
('ENSERES',     110, '216', 'Otros enseres', 'Other fixtures', 15, 14),
('ELECTRONICA', 120, '219', 'Equipos electrónicos', 'Electronic equipment', 20, 10),
('INFORMATICA', 130, '217', 'Equipos para procesos de información', 'Computer equipment', 25, 8),
('SOFTWARE',    140, '206', 'Sistemas y programas informáticos', 'Software', 33, 6),
('TRANSPORTE',  150, '218', 'Elementos de transporte externo', 'External transport vehicles', 16, 14),
('CAMIONES',    160, '218', 'Autocamiones', 'Trucks', 20, 10),
('TRANSP_INT',  170, '218', 'Elementos de transporte interno', 'Internal transport vehicles', 10, 20),
('OTROS',       180, '219', 'Demás elementos', 'Other assets', 10, 20)
on conflict (code) do update set sort = excluded.sort, pgc_prefix = excluded.pgc_prefix, name = excluded.name,
  name_en = excluded.name_en, max_pct = excluded.max_pct, max_years = excluded.max_years;
alter table erp.depreciation_classes enable row level security;
drop policy if exists read on erp.depreciation_classes;
create policy read on erp.depreciation_classes for select to authenticated using (true);
revoke all on erp.depreciation_classes from anon, public;
grant select on erp.depreciation_classes to authenticated;

-- ---------------------------------------------------------------------
-- 2) Fichas de activos y amortizaciones contabilizadas
-- ---------------------------------------------------------------------
create table if not exists erp.fixed_assets (
  id                      uuid primary key default gen_random_uuid(),
  company_id              uuid not null references erp.companies(id) on delete cascade,
  code                    text not null,
  name                    text not null,
  class_code              text references erp.depreciation_classes(code),
  asset_account_id        uuid not null references erp.gl_accounts(id),
  depreciation_account_id uuid not null references erp.gl_accounts(id),
  expense_account_id      uuid not null references erp.gl_accounts(id),
  acquisition_date        date not null,
  start_date              date not null,                       -- puesta en condiciones de funcionamiento
  cost                    numeric(15,2) not null check (cost > 0),
  residual_value          numeric(15,2) not null default 0 check (residual_value >= 0),
  useful_life_months      int not null check (useful_life_months > 0),
  invoice_id              uuid references erp.invoices(id),
  status                  text not null default 'active' check (status in ('active', 'disposed')),
  disposal_date           date,
  disposal_price          numeric(15,2),
  disposal_invoice_id     uuid references erp.invoices(id),
  disposal_entry_id       uuid references erp.journal_entries(id),
  created_at              timestamptz not null default now(),
  unique (company_id, code),
  check (residual_value < cost),
  check (start_date >= acquisition_date)
);
create index if not exists fixed_assets_company_idx on erp.fixed_assets (company_id);
create index if not exists fixed_assets_class_idx on erp.fixed_assets (class_code);
create index if not exists fixed_assets_asset_acc_idx on erp.fixed_assets (asset_account_id);
create index if not exists fixed_assets_dep_acc_idx on erp.fixed_assets (depreciation_account_id);
create index if not exists fixed_assets_exp_acc_idx on erp.fixed_assets (expense_account_id);
create index if not exists fixed_assets_invoice_idx on erp.fixed_assets (invoice_id);
create index if not exists fixed_assets_disp_inv_idx on erp.fixed_assets (disposal_invoice_id);
create index if not exists fixed_assets_disp_entry_idx on erp.fixed_assets (disposal_entry_id);

create table if not exists erp.asset_depreciations (
  id          uuid primary key default gen_random_uuid(),
  asset_id    uuid not null references erp.fixed_assets(id) on delete cascade,
  company_id  uuid not null references erp.companies(id) on delete cascade,
  period_end  date not null,
  amount      numeric(15,2) not null check (amount > 0),
  entry_id    uuid not null references erp.journal_entries(id),
  unique (asset_id, period_end)
);
create index if not exists asset_depreciations_company_idx on erp.asset_depreciations (company_id);
create index if not exists asset_depreciations_entry_idx on erp.asset_depreciations (entry_id);

alter table erp.fixed_assets enable row level security;
alter table erp.asset_depreciations enable row level security;
drop policy if exists read on erp.fixed_assets;
drop policy if exists read on erp.asset_depreciations;
create policy read on erp.fixed_assets for select to authenticated using (erp.can_read(company_id));
create policy read on erp.asset_depreciations for select to authenticated using (erp.can_read(company_id));
revoke all on erp.fixed_assets, erp.asset_depreciations from anon, public;
grant select on erp.fixed_assets, erp.asset_depreciations to authenticated;   -- se escriben solo con las funciones

-- ---------------------------------------------------------------------
-- 3) Cálculo: amortización acumulada a una fecha (lineal, por meses; el primer mes, por días)
--    base = coste − valor residual · fracción = meses enteros desde la puesta en funcionamiento + días / días del mes
-- ---------------------------------------------------------------------
create or replace function erp.asset_accumulated_at(p_cost numeric, p_residual numeric, p_life int, p_start date, p_date date)
returns numeric language sql immutable as $$
  with a as (select p_cost - p_residual as base, (p_date + 1) as d1),
  m as (select a.*, (extract(year from age(a.d1, p_start)) * 12 + extract(month from age(a.d1, p_start)))::int as months from a),
  f as (select m.*, (p_start + make_interval(months => m.months))::date as from_d,
               (p_start + make_interval(months => m.months + 1))::date as to_d from m)
  select case when p_date < p_start then 0
              else least(f.base, round(f.base * (f.months + (f.d1 - f.from_d)::numeric / (f.to_d - f.from_d)) / p_life, 2)) end
  from f;
$$;

-- Cuadro de amortización: un año por fila (a 31 de diciembre), hasta quedar amortizado
create or replace function erp.depreciation_schedule(p_asset uuid)
returns table (year int, amount numeric, accumulated numeric, net_book_value numeric)
language sql stable as $$
  with a as (select * from erp.fixed_assets where id = p_asset),
  y as (select generate_series(extract(year from a.start_date)::int,
                               extract(year from (a.start_date + make_interval(months => a.useful_life_months)))::int) as yr from a),
  c as (select y.yr, erp.asset_accumulated_at(a.cost, a.residual_value, a.useful_life_months, a.start_date, make_date(y.yr, 12, 31)) as acc
        from y cross join a)
  select c.yr, c.acc - coalesce(lag(c.acc) over (order by c.yr), 0), c.acc, (select cost from a) - c.acc
  from c
  where c.acc - coalesce((select c2.acc from c c2 where c2.yr = c.yr - 1), 0) > 0
  order by c.yr;
$$;

-- Lo ya contabilizado de un activo
create or replace function erp.asset_posted(p_asset uuid)
returns numeric language sql stable as $$
  select coalesce(sum(d.amount), 0) from erp.asset_depreciations d where d.asset_id = p_asset;
$$;

-- ---------------------------------------------------------------------
-- 4) Alta de un activo
--   p: { company_id, name, asset_account_no, cost, residual_value, start_date, acquisition_date, useful_life_months,
--        class_code, invoice_id }  →  { asset_id, code, warnings: [ … ] }
-- ---------------------------------------------------------------------
create or replace function erp.asset_account_pair(p_company uuid, p_asset_no text, p_kind text)
returns uuid language plpgsql security definer set search_path = erp, public as $$
-- 2x → su amortización acumulada (28x: 21x → 281x, 20x → 280x, 22x → 282x) o su gasto (68x)
declare
  v_digits int := (select posting_account_digits from erp.companies where id = p_company);
  v_no     text;
  v_id     uuid;
begin
  v_no := case p_kind
    when 'depreciation' then rpad('28' || substr(p_asset_no, 2, 1) || substr(p_asset_no, 3, 1), v_digits - 1, '0') || '1'
    else rpad('68' || substr(p_asset_no, 2, 1), v_digits - 1, '0') || '1' end;
  select id into v_id from erp.gl_accounts where company_id = p_company and account_no = v_no;
  if v_id is null then
    perform erp.create_posting_account(p_company, v_no,
      case p_kind when 'depreciation' then 'Amortización acumulada · ' || (select name from erp.gl_accounts where company_id = p_company and account_no = p_asset_no)
                  else (select name from erp.gl_accounts where company_id = p_company and account_no = rpad(left(v_no, 3), 3, '0')) end);
    select id into v_id from erp.gl_accounts where company_id = p_company and account_no = v_no;
  end if;
  return v_id;
end $$;

create or replace function erp.create_fixed_asset(p jsonb)
returns table (asset_id uuid, code text, warnings jsonb)
language plpgsql security definer set search_path = erp, public as $$
declare
  v_company uuid := (p->>'company_id')::uuid;
  v_acc     erp.gl_accounts;
  v_class   erp.depreciation_classes;
  v_life    int := (p->>'useful_life_months')::int;
  v_start   date := (p->>'start_date')::date;
  v_acq     date := coalesce((p->>'acquisition_date')::date, (p->>'start_date')::date);
  v_cost    numeric := round((p->>'cost')::numeric, 2);
  v_res     numeric := round(coalesce((p->>'residual_value')::numeric, 0), 2);
  v_code    text;
  v_id      uuid;
  v_warn    jsonb := '[]';
  v_pct     numeric;
begin
  if not erp.can_write(v_company) then raise exception 'No permission to register fixed assets in this company'; end if;
  if coalesce(btrim(p->>'name'), '') = '' then raise exception 'The asset needs a name'; end if;
  select * into v_acc from erp.gl_accounts
  where company_id = v_company and account_no = p->>'asset_account_no' and account_type = 'posting';
  if not found or left(v_acc.account_no, 2) not in ('20', '21', '22') then
    raise exception 'Choose the asset account (20x, 21x or 22x)';
  end if;
  if left(v_acc.account_no, 3) in ('210', '220') then
    raise exception 'Land is not depreciated (NRV 2.ª): account % cannot be a depreciable asset', v_acc.account_no;
  end if;
  if v_cost is null or v_cost <= 0 then raise exception 'The cost must be greater than zero'; end if;
  if v_res < 0 or v_res >= v_cost then raise exception 'The residual value must be between zero and the cost'; end if;
  if v_life is null or v_life <= 0 then raise exception 'The useful life must be at least one month'; end if;
  if v_start is null then raise exception 'The start date (when the asset is ready for use) is required'; end if;
  if v_start < v_acq then raise exception 'The start date cannot be earlier than the acquisition date'; end if;
  if p->>'invoice_id' is not null and not exists (select 1 from erp.invoices i where i.id = (p->>'invoice_id')::uuid
       and i.company_id = v_company and i.invoice_type = 'purchase') then
    raise exception 'The invoice must be a received invoice of this company';
  end if;

  -- Coeficiente fiscal (LIS art. 12.1.a): el contable puede ser distinto; si supera el máximo o queda por debajo del
  -- mínimo (1 / período máximo), la diferencia se ajusta en el Impuesto sobre Sociedades
  if p->>'class_code' is not null then
    select * into v_class from erp.depreciation_classes where depreciation_classes.code = p->>'class_code';
    if not found then raise exception 'Unknown depreciation class: %', p->>'class_code'; end if;
    v_pct := round(1200.0 / v_life, 2);
    if v_pct > v_class.max_pct then
      v_warn := v_warn || jsonb_build_object('code', 'above_tax_max', 'rate', v_pct, 'max', v_class.max_pct);
    end if;
    if v_life > v_class.max_years * 12 then
      v_warn := v_warn || jsonb_build_object('code', 'below_tax_min', 'years', round(v_life / 12.0, 1), 'max_years', v_class.max_years);
    end if;
  end if;

  select 'INM-' || lpad((count(*) + 1)::text, 4, '0') into v_code from erp.fixed_assets where company_id = v_company;
  insert into erp.fixed_assets (company_id, code, name, class_code, asset_account_id, depreciation_account_id, expense_account_id,
                                acquisition_date, start_date, cost, residual_value, useful_life_months, invoice_id)
  values (v_company, v_code, btrim(p->>'name'), p->>'class_code', v_acc.id,
          erp.asset_account_pair(v_company, v_acc.account_no, 'depreciation'), erp.asset_account_pair(v_company, v_acc.account_no, 'expense'),
          v_acq, v_start, v_cost, v_res, v_life, (p->>'invoice_id')::uuid)
  returning id into v_id;
  asset_id := v_id; code := v_code; warnings := v_warn;
  return next;
end $$;

-- ---------------------------------------------------------------------
-- 5) Amortización del periodo: un asiento con todos los activos, hasta una fecha (normalmente fin de mes)
-- ---------------------------------------------------------------------
create or replace function erp.post_depreciation(p_company uuid, p_date date)
returns table (entry_no int, assets int, amount numeric)
language plpgsql security definer set search_path = erp, public as $$
declare
  v_fy    uuid;
  v_entry uuid;
  v_no    int;
  v_n     int := 0;
  v_sum   numeric := 0;
  r       record;
  v_line  int := 0;
begin
  if not erp.can_write(p_company) then raise exception 'No permission to register fixed assets in this company'; end if;
  select id into v_fy from erp.fiscal_years where company_id = p_company and p_date between starting_date and ending_date;
  if v_fy is null then raise exception 'No fiscal year for date %', p_date; end if;

  for r in
    select a.*, erp.asset_accumulated_at(a.cost, a.residual_value, a.useful_life_months, a.start_date, p_date) - erp.asset_posted(a.id) as due
    from erp.fixed_assets a
    where a.company_id = p_company and a.status = 'active' and a.start_date <= p_date
      and not exists (select 1 from erp.asset_depreciations d where d.asset_id = a.id and d.period_end >= p_date)
    order by a.code
  loop
    if r.due <= 0 then continue; end if;
    if v_entry is null then
      insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
      values (p_company, v_fy, p_date, 'Amortización del inmovilizado hasta el ' || to_char(p_date, 'DD/MM/YYYY'))
      returning id into v_entry;
    end if;
    insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description) values
      (v_entry, p_company, v_line + 1, r.expense_account_id, r.due, 0, r.code || ' · ' || r.name),
      (v_entry, p_company, v_line + 2, r.depreciation_account_id, 0, r.due, r.code || ' · ' || r.name);
    v_line := v_line + 2;
    insert into erp.asset_depreciations (asset_id, company_id, period_end, amount, entry_id)
    values (r.id, p_company, p_date, r.due, v_entry);
    v_n := v_n + 1; v_sum := v_sum + r.due;
  end loop;
  if v_entry is null then raise exception 'Nothing to depreciate up to %', p_date; end if;
  perform set_config('erp.asset_engine', 'on', true);
  v_no := erp.post_entry(v_entry);
  perform set_config('erp.asset_engine', 'off', true);
  entry_no := v_no; assets := v_n; amount := v_sum;
  return next;
end $$;

-- Deshacer la ÚLTIMA amortización (contraasiento; los activos vuelven a quedar pendientes de ese periodo)
create or replace function erp.cancel_depreciation(p_entry uuid, p_date date default null)
returns int language plpgsql security definer set search_path = erp, public as $$
declare v_company uuid; v_no int; v_end date;
begin
  select d.company_id, max(d.period_end) into v_company, v_end from erp.asset_depreciations d where d.entry_id = p_entry group by d.company_id;
  if v_company is null then raise exception 'This entry is not a depreciation'; end if;
  if not erp.can_write(v_company) then raise exception 'No permission to register fixed assets in this company'; end if;
  if exists (select 1 from erp.fixed_assets a where a.disposal_entry_id = p_entry) then
    raise exception 'This depreciation belongs to a disposal: cancel the disposal instead';
  end if;
  if exists (select 1 from erp.asset_depreciations d where d.company_id = v_company and d.period_end > v_end) then
    raise exception 'Only the last depreciation can be cancelled';
  end if;
  perform set_config('erp.asset_engine', 'on', true);
  v_no := erp.reverse_entry(p_entry, coalesce(p_date, (select posting_date from erp.journal_entries where id = p_entry)), 'Amortización anulada');
  perform set_config('erp.asset_engine', 'off', true);
  delete from erp.asset_depreciations where entry_id = p_entry;
  return v_no;
end $$;

-- ---------------------------------------------------------------------
-- 6) Baja de un activo (venta, si se indica la factura emitida; si no, retiro: obsolescencia, siniestro…)
--   Asiento (NRV 2.ª): 68x D / 28x H  amortización hasta la fecha
--                      28x D        toda la amortización acumulada
--                      2x  H        coste − lo ya abonado por la factura de venta (la factura lleva el precio al Haber)
--                      67x D / 77x H  la diferencia: precio − valor neto contable
-- ---------------------------------------------------------------------
-- 670/671/672 pérdidas · 770/771/772 beneficios (según 20x/21x/22x), creando la subcuenta si falta
create or replace function erp.asset_result_account(p_company uuid, p_asset_no text, p_result numeric)
returns uuid language plpgsql security definer set search_path = erp, public as $$
declare
  v_digits int := (select posting_account_digits from erp.companies where id = p_company);
  v_pgc    text := case when p_result < 0 then '67' else '77' end || substr(p_asset_no, 2, 1);
  v_no     text := rpad(v_pgc, v_digits - 1, '0') || '1';
  v_id     uuid;
begin
  select id into v_id from erp.gl_accounts where company_id = p_company and account_no = v_no;
  if v_id is null then
    perform erp.create_posting_account(p_company, v_no, (select name from erp.gl_accounts where company_id = p_company and account_no = v_pgc));
    select id into v_id from erp.gl_accounts where company_id = p_company and account_no = v_no;
  end if;
  return v_id;
end $$;

create or replace function erp.dispose_asset(p jsonb)
returns table (entry_no int, net_book_value numeric, result numeric)
language plpgsql security definer set search_path = erp, public as $$
declare
  a        erp.fixed_assets;
  v_date   date := (p->>'disposal_date')::date;
  v_inv    erp.invoices;
  v_price  numeric := 0;
  v_fy     uuid;
  v_entry  uuid;
  v_catch  numeric;
  v_acc    numeric;
  v_nbv    numeric;
  v_res    numeric;
  v_digits int;
  v_no     int;
  v_line   int := 0;
begin
  select * into a from erp.fixed_assets where id = (p->>'asset_id')::uuid;
  if not found then raise exception 'Asset not found'; end if;
  if not erp.can_write(a.company_id) then raise exception 'No permission to register fixed assets in this company'; end if;
  if a.status <> 'active' then raise exception 'Asset % is already disposed', a.code; end if;
  if v_date is null then raise exception 'The disposal date is required'; end if;
  if v_date < a.start_date then raise exception 'The disposal date cannot be earlier than the start date'; end if;
  if exists (select 1 from erp.asset_depreciations d where d.asset_id = a.id and d.period_end > v_date) then
    raise exception 'Asset % is already depreciated after %: cancel that depreciation first', a.code, v_date;
  end if;
  select id into v_fy from erp.fiscal_years where company_id = a.company_id and v_date between starting_date and ending_date;
  if v_fy is null then raise exception 'No fiscal year for date %', v_date; end if;

  -- Factura de venta: emitida, de esta empresa, y con su línea en la cuenta del activo (eso es el precio)
  if p->>'invoice_id' is not null then
    select * into v_inv from erp.invoices i where i.id = (p->>'invoice_id')::uuid and i.company_id = a.company_id;
    if not found or v_inv.invoice_type <> 'sale' then raise exception 'The sale must be an issued invoice of this company'; end if;
    select coalesce(sum(l.amount * l.sign), 0) into v_price from erp.invoice_lines l
    where l.invoice_id = v_inv.id and l.gl_account_id = a.asset_account_id;
    if v_price <= 0 then raise exception 'Invoice % has no line on the asset account', v_inv.invoice_no; end if;
    if exists (select 1 from erp.fixed_assets x where x.disposal_invoice_id = v_inv.id) then
      raise exception 'Invoice % is already used for another disposal', v_inv.invoice_no;
    end if;
  end if;

  v_catch := erp.asset_accumulated_at(a.cost, a.residual_value, a.useful_life_months, a.start_date, v_date) - erp.asset_posted(a.id);
  v_acc := erp.asset_posted(a.id) + greatest(v_catch, 0);
  v_nbv := a.cost - v_acc;
  v_res := v_price - v_nbv;
  v_digits := (select posting_account_digits from erp.companies where id = a.company_id);

  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no)
  values (a.company_id, v_fy, v_date, left(case when v_inv.id is null then 'Baja de ' else 'Venta de ' end || a.code || ' · ' || a.name, 250),
          v_inv.invoice_no)
  returning id into v_entry;
  if v_catch > 0 then
    insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description) values
      (v_entry, a.company_id, 1, a.expense_account_id, v_catch, 0, 'Amortización hasta la baja'),
      (v_entry, a.company_id, 2, a.depreciation_account_id, 0, v_catch, 'Amortización hasta la baja');
    v_line := 2;
    insert into erp.asset_depreciations (asset_id, company_id, period_end, amount, entry_id)
    values (a.id, a.company_id, v_date, v_catch, v_entry);
  end if;
  if v_acc > 0 then
    insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description)
    values (v_entry, a.company_id, v_line + 1, a.depreciation_account_id, v_acc, 0, 'Cancelación de la amortización acumulada');
    v_line := v_line + 1;
  end if;
  if a.cost - v_price <> 0 then
    insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description)
    values (v_entry, a.company_id, v_line + 1, a.asset_account_id,
            greatest(v_price - a.cost, 0), greatest(a.cost - v_price, 0), 'Baja del activo');
    v_line := v_line + 1;
  end if;
  if v_res <> 0 then
    insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description)
    values (v_entry, a.company_id, v_line + 1,
            erp.asset_result_account(a.company_id, (select account_no from erp.gl_accounts where id = a.asset_account_id), v_res),
            greatest(-v_res, 0), greatest(v_res, 0), case when v_res < 0 then 'Pérdida' else 'Beneficio' end || ' en la baja');
  end if;
  perform set_config('erp.asset_engine', 'on', true);
  v_no := erp.post_entry(v_entry);
  perform set_config('erp.asset_engine', 'off', true);

  update erp.fixed_assets set status = 'disposed', disposal_date = v_date, disposal_price = v_price,
                              disposal_invoice_id = v_inv.id, disposal_entry_id = v_entry
  where id = a.id;
  entry_no := v_no; net_book_value := v_nbv; result := v_res;
  return next;
end $$;

-- Deshacer una baja: contraasiento y el activo vuelve a estar en uso (la factura de venta, si la hay, se rectifica aparte)
create or replace function erp.cancel_disposal(p_asset uuid, p_date date default null)
returns int language plpgsql security definer set search_path = erp, public as $$
declare a erp.fixed_assets; v_no int;
begin
  select * into a from erp.fixed_assets where id = p_asset;
  if not found then raise exception 'Asset not found'; end if;
  if not erp.can_write(a.company_id) then raise exception 'No permission to register fixed assets in this company'; end if;
  if a.status <> 'disposed' then raise exception 'Asset % is not disposed', a.code; end if;
  perform set_config('erp.asset_engine', 'on', true);
  v_no := erp.reverse_entry(a.disposal_entry_id, coalesce(p_date, a.disposal_date), 'Baja anulada');
  perform set_config('erp.asset_engine', 'off', true);
  delete from erp.asset_depreciations where entry_id = a.disposal_entry_id;
  update erp.fixed_assets set status = 'active', disposal_date = null, disposal_price = null,
                              disposal_invoice_id = null, disposal_entry_id = null
  where id = a.id;
  return v_no;
end $$;

-- Los asientos del inmovilizado no se anulan sueltos desde el diario (como los de facturas y pagos)
create or replace function erp.tg_entry_asset_reverse()
returns trigger language plpgsql as $$
begin
  if new.reversal_of is not null and coalesce(current_setting('erp.asset_engine', true), '') <> 'on'
     and (exists (select 1 from erp.asset_depreciations where entry_id = new.reversal_of)
          or exists (select 1 from erp.fixed_assets where disposal_entry_id = new.reversal_of)) then
    raise exception 'This entry belongs to the fixed assets module: cancel it from Fixed assets';
  end if;
  return new;
end $$;
drop trigger if exists entry_asset_reverse on erp.journal_entries;
create trigger entry_asset_reverse before insert on erp.journal_entries
  for each row execute function erp.tg_entry_asset_reverse();

-- ---------------------------------------------------------------------
-- 7) Cuentas controladas (0036): el inmovilizado y su amortización los mueve este módulo
--    (la compra y la venta, la factura; el resto, Inmovilizado)
-- ---------------------------------------------------------------------
insert into erp.control_rules (account_prefix, modules, side, note, note_en) values
('20',  '{invoices,assets}', 'both', 'Inmovilizado intangible: lo da de alta la factura recibida y de baja el módulo de Inmovilizado.', 'Intangible assets: acquired by the received invoice and disposed of by Fixed assets.'),
('21',  '{invoices,assets}', 'both', 'Inmovilizado material: lo da de alta la factura recibida y de baja el módulo de Inmovilizado.', 'Property, plant and equipment: acquired by the received invoice and disposed of by Fixed assets.'),
('22',  '{invoices,assets}', 'both', 'Inversiones inmobiliarias: alta con la factura recibida, baja con el módulo de Inmovilizado.', 'Investment property: acquired by the received invoice and disposed of by Fixed assets.'),
('28',  '{assets}',          'both', 'Amortización acumulada: la mueven la amortización y la baja del módulo de Inmovilizado.', 'Accumulated depreciation: posted by the depreciation and disposal of Fixed assets.')
on conflict (account_prefix) do update set modules = excluded.modules, side = excluded.side, note = excluded.note, note_en = excluded.note_en;

-- Los asientos del módulo no son manuales
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
  from erp.journal_entries e where e.id = p_entry;
$$;

-- ---------------------------------------------------------------------
-- 8) Versiones nuevas de funciones existentes (copiadas de la vigente; cambia solo lo marcado «v0.35.0»)
-- ---------------------------------------------------------------------
-- El diario y las comprobaciones saben qué asientos son del inmovilizado
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
$function$
;;

-- Borrar una empresa: las fichas apuntan a asientos y facturas, se borran antes
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
;;

-- La venta de un activo, con factura emitida a su cuenta
CREATE OR REPLACE FUNCTION erp.invoice_entry_lines(p jsonb)
 RETURNS TABLE(line_no integer, gl_account_id uuid, account_no text, account_name text, debit numeric, credit numeric, tax_code text, tax_base numeric, line_role text, src_line integer, amount numeric, sign integer, description text)
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_company   uuid := (p->>'company_id')::uuid;
  v_type      text := p->>'invoice_type';
  v_kind      text := coalesce(p->>'document_kind', 'invoice');
  v_partner   erp.business_partners;
  v_pacc      erp.gl_accounts;
  v_work      jsonb := '[]'::jsonb;   -- líneas ya validadas (sin tablas temporales)
  v_total     numeric := 0;
  v_n         int := 0;
  v_signed    numeric;
  v_sign      int;
  r           record;
  t           record;
  a           erp.gl_accounts;
  s           erp.tax_setup;
  tc          erp.tax_codes;
  v_comp      erp.companies;
  v_wh_code   text := nullif(btrim(p->>'withholding_code'), '');
  v_wh        erp.withholding_codes;
  v_whs       erp.withholding_setup;
  v_base_total numeric := 0;
  v_wh_amt    numeric := 0;
  v_nd        boolean;              -- compras de un comerciante en recargo de equivalencia: nada es deducible
  v_re        numeric;
  v_side_acc  uuid;
  v_posting   date := coalesce(nullif(p->>'posting_date', ''), p->>'invoice_date')::date;
  v_pr        numeric;              -- prorrata provisional del año (null = deducción total)
  v_ded       numeric;
begin
  if v_type is null or v_type not in ('purchase', 'sale') then
    raise exception 'Invalid invoice type: %', v_type;
  end if;
  if v_kind not in ('invoice', 'credit_memo') then
    raise exception 'Invalid document kind: %', v_kind;
  end if;

  -- Tercero: proveedor/acreedor en compras, cliente/deudor en ventas
  select * into v_partner from erp.business_partners bp
  where bp.id = nullif(p->>'partner_id', '')::uuid and bp.company_id = v_company;
  if not found then
    raise exception 'Choose the partner of the invoice';
  end if;
  if v_type = 'purchase' and v_partner.partner_type not in ('vendor', 'creditor') then
    raise exception 'A received invoice needs a vendor (400) or creditor (410), not a %', v_partner.partner_type;
  end if;
  if v_type = 'sale' and v_partner.partner_type not in ('customer', 'debtor') then
    raise exception 'An issued invoice needs a customer (430) or debtor (440), not a %', v_partner.partner_type;
  end if;
  if v_partner.blocked then
    raise exception 'Partner % is blocked', v_partner.name;
  end if;
  select * into v_pacc from erp.gl_accounts g where g.id = v_partner.gl_account_id;
  if v_pacc.id is null then
    raise exception 'Partner % has no posting account', v_partner.name;
  end if;

  select * into v_comp from erp.companies c where c.id = v_company;
  v_nd := v_comp.vat_regime = 'equivalence_surcharge' and v_type = 'purchase';

  -- Retención IRPF (opcional): debe existir y estar configurada en la empresa
  if v_wh_code is not null then
    select * into v_wh from erp.withholding_codes w where w.code = v_wh_code;
    if not found then
      raise exception 'Unknown withholding code %', v_wh_code;
    end if;
    select * into v_whs from erp.withholding_setup ws where ws.company_id = v_company and ws.withholding_code = v_wh_code;
    if not found or v_whs.blocked then
      raise exception 'Withholding % is not set up for this company (Taxes tab)', v_wh_code;
    end if;
  end if;

  if jsonb_array_length(coalesce(p->'lines', '[]'::jsonb)) = 0 then
    raise exception 'The invoice has no lines';
  end if;

  -- 0) Validar y resolver cada línea
  for r in
    select x.ord::int as n, btrim(x.l->>'account_no') as acc_no, x.l->>'amount' as amount_txt,
           x.l->>'tax_code' as code, nullif(btrim(x.l->>'description'), '') as descr
    from jsonb_array_elements(p->'lines') with ordinality as x(l, ord)
  loop
    select * into a from erp.gl_accounts g where g.company_id = v_company and g.account_no = r.acc_no;
    if not found then
      raise exception 'Line %: account % does not exist', r.n, coalesce(r.acc_no, '');
    end if;
    if a.account_type <> 'posting' then
      raise exception 'Line %: account % is a heading account', r.n, a.account_no;
    end if;
    -- Regla contable: compras a grupos 2 (inmovilizado) o 6 (gastos); ventas al grupo 7 (ingresos)
    if v_type = 'purchase' and left(a.account_no, 1) not in ('2', '6') then
      raise exception 'Line %: account % is not valid in a received invoice (use group 6 or 2)', r.n, a.account_no;
    end if;
    -- v0.35.0: la venta de un inmovilizado se factura a su cuenta (20x / 21x / 22x); la baja la hace el módulo
    if v_type = 'sale' and left(a.account_no, 1) <> '7' and left(a.account_no, 2) not in ('20', '21', '22') then
      raise exception 'Line %: account % is not valid in an issued invoice (use group 7, or the asset account to sell a fixed asset)', r.n, a.account_no;
    end if;
    if coalesce(nullif(r.amount_txt, '')::numeric, 0) <= 0 then
      raise exception 'Line %: the amount must be greater than zero', r.n;
    end if;

    select * into tc from erp.tax_codes c where c.code = r.code;
    if not found then
      raise exception 'Line %: choose a tax code', r.n;
    end if;
    select * into s from erp.tax_setup ts where ts.company_id = v_company and ts.tax_code = r.code;
    if not found or s.blocked then
      raise exception 'Line %: tax code % is not set up for this company (Taxes tab)', r.n, r.code;
    end if;

    -- Operaciones sin cuota: cada causa tiene sus condiciones (lo que comprobaría un inspector)
    if tc.rate_category in ('export', 'intra_eu') and v_type <> 'sale' then
      raise exception 'Line %: % (export / intra-EU supply) is only for issued invoices', r.n, r.code;
    end if;
    if tc.rate_category = 'intra_eu' and v_partner.tax_territory <> 'eu' then
      raise exception 'Line %: an intra-EU supply (%) needs a customer from another EU country', r.n, r.code;
    end if;
    if tc.rate_category = 'export' and v_comp.tax_territory = 'mainland' and v_partner.tax_territory = 'eu' then
      raise exception 'Line %: a sale of goods to another EU country is an intra-EU supply, not an export', r.n;
    end if;
    if tc.rate_category in ('export', 'not_subject') and v_partner.tax_territory = v_comp.tax_territory then
      raise exception 'Line %: % is only for partners outside the company tax territory (%)', r.n, r.code, v_comp.tax_territory;
    end if;

    -- Inversión del sujeto pasivo y adquisición intracomunitaria: solo en compras
    if tc.rate_category in ('reverse_charge', 'intra_eu_acquisition') and v_type <> 'purchase' then
      raise exception 'Line %: % (reverse charge) is only for received invoices', r.n, r.code;
    end if;
    if tc.rate_category = 'intra_eu_acquisition' and v_partner.tax_territory <> 'eu' then
      raise exception 'Line %: an intra-EU acquisition (%) needs a vendor from another EU country', r.n, r.code;
    end if;
    if tc.rate_category in ('reverse_charge', 'intra_eu_acquisition') and v_comp.vat_regime = 'equivalence_surcharge' then
      raise exception 'Line %: reverse charge is not available for a retailer under the equivalence surcharge in this lab', r.n;
    end if;
    -- Recargo de equivalencia: el minorista vende con el IVA incluido en el precio (no lo liquida)
    if tc.rate_category = 'retail_surcharge' and not (v_comp.vat_regime = 'equivalence_surcharge' and v_type = 'sale') then
      raise exception 'Line %: % is only for sales of a retailer under the equivalence surcharge', r.n, r.code;
    end if;
    if v_comp.vat_regime = 'equivalence_surcharge' and v_type = 'sale' and tc.rate_pct > 0 then
      raise exception 'Line %: a retailer under the equivalence surcharge records its sales with VAT included (code VAT_RE_INC)', r.n;
    end if;
    if v_type = 'sale' and v_partner.equivalence_surcharge and tc.equivalence_surcharge_pct is not null
       and s.surcharge_account_id is null then
      raise exception 'Line %: the equivalence surcharge account for % is not set up (Taxes: run the setup again)', r.n, r.code;
    end if;

    -- Regla del lado: reducen las cuentas 606/608/609 · 706/708/709 y todas las líneas de una rectificativa
    v_sign := case when v_kind = 'credit_memo'
                     or a.template_account in ('606', '608', '609', '706', '708', '709') then -1 else 1 end;

    v_work := v_work || jsonb_build_object(
      'n', r.n, 'gl_account_id', a.id, 'account_no', a.account_no, 'account_name', a.name,
      'amount', round(r.amount_txt::numeric, 2), 'tax_code', r.code, 'sign', v_sign, 'rate', tc.rate_pct,
      'description', r.descr,
      'cat', tc.rate_category, 're_pct', tc.equivalence_surcharge_pct, 'ttype', tc.tax_type,
      'in_acc', s.input_account_id, 'out_acc', s.output_account_id, 're_acc', s.surcharge_account_id);
  end loop;

  -- 1) Líneas de base: compras aumentan al DEBE · ventas aumentan al HABER
  for r in select * from jsonb_to_recordset(v_work)
             as w(n int, gl_account_id uuid, account_no text, account_name text, amount numeric,
                  tax_code text, sign int, description text) order by n
  loop
    v_n := v_n + 1;
    v_signed := r.sign * r.amount;
    v_total := v_total + v_signed;
    line_no := v_n; gl_account_id := r.gl_account_id; account_no := r.account_no; account_name := r.account_name;
    debit  := case when (v_type = 'purchase') = (v_signed > 0) then abs(v_signed) else 0 end;
    credit := case when (v_type = 'purchase') = (v_signed > 0) then 0 else abs(v_signed) end;
    tax_code := r.tax_code; tax_base := null; line_role := 'base';
    src_line := r.n; amount := r.amount; sign := r.sign; description := r.description;
    return next;
  end loop;

  v_base_total := v_total;   -- base imponible neta de la factura (con signo)

  -- 2) Cuotas: una por tipo, sobre la base neta de la factura, redondeada a céntimos
  for t in
    select w.tax_code as code, max(w.rate) as rate, max(w.re_pct) as re_pct, max(w.cat) as cat, max(w.ttype) as ttype,
           sum(w.sign * w.amount) as base,
           (array_agg(w.in_acc))[1] as in_acc, (array_agg(w.out_acc))[1] as out_acc, (array_agg(w.re_acc))[1] as re_acc,
           (array_agg(w.gl_account_id order by w.n))[1] as first_acc
    from jsonb_to_recordset(v_work) as w(n int, tax_code text, rate numeric, re_pct numeric, cat text, ttype text, sign int,
                                         amount numeric, in_acc uuid, out_acc uuid, re_acc uuid, gl_account_id uuid)
    group by w.tax_code order by w.tax_code
  loop
    v_signed := round(t.base * t.rate / 100, 2);
    src_line := null; amount := null; sign := null; description := null;
    tax_code := t.code; tax_base := t.base;

    if v_signed = 0 then
      -- tipo 0 % o sin cuota: no hay apunte, pero sí base para el libro registro
      line_no := null; gl_account_id := null; account_no := null; account_name := null;
      debit := 0; credit := 0; line_role := 'tax_exempt';
      return next;
      continue;
    end if;

    -- Prorrata: en las compras solo se deduce el porcentaje provisional del año; el resto es más coste
    v_pr := null;
    if v_type = 'purchase' and not v_nd then
      select pr.provisional_pct into v_pr from erp.pro_rata pr
      where pr.company_id = v_company and pr.tax_type = t.ttype and pr.year = extract(year from v_posting);
    end if;
    v_ded := case when v_pr is null then v_signed else round(v_signed * v_pr / 100, 2) end;

    if t.cat in ('reverse_charge', 'intra_eu_acquisition') then
      -- ISP / adquisición intracomunitaria: la EMPRESA se repercute y se soporta la cuota.
      -- 472 al Debe y 477 al Haber por el mismo importe; el proveedor no la cobra (no suma al total)
      if v_ded <> 0 then
        v_n := v_n + 1;
        line_no := v_n; gl_account_id := t.in_acc;
        select g.account_no, g.name into account_no, account_name from erp.gl_accounts g where g.id = t.in_acc;
        debit  := case when v_ded > 0 then v_ded else 0 end;
        credit := case when v_ded > 0 then 0 else -v_ded end;
        line_role := 'tax';
        return next;
      end if;
      if v_signed - v_ded <> 0 then   -- parte no deducible por la prorrata: a la cuenta de la compra
        v_n := v_n + 1;
        line_no := v_n; gl_account_id := t.first_acc;
        select g.account_no, g.name into account_no, account_name from erp.gl_accounts g where g.id = t.first_acc;
        debit  := case when v_signed - v_ded > 0 then v_signed - v_ded else 0 end;
        credit := case when v_signed - v_ded > 0 then 0 else v_ded - v_signed end;
        line_role := 'tax_nd';
        return next;
      end if;
      v_n := v_n + 1;
      line_no := v_n; gl_account_id := t.out_acc;
      select g.account_no, g.name into account_no, account_name from erp.gl_accounts g where g.id = t.out_acc;
      debit  := case when v_signed > 0 then 0 else -v_signed end;
      credit := case when v_signed > 0 then v_signed else 0 end;
      line_role := 'tax_rc';
      return next;
      continue;
    end if;

    v_total := v_total + v_signed;
    if v_pr is not null then
      -- Prorrata: 472 por la parte deducible y la cuenta de la compra por el resto
      if v_ded <> 0 then
        v_n := v_n + 1;
        line_no := v_n; gl_account_id := t.in_acc;
        select g.account_no, g.name into account_no, account_name from erp.gl_accounts g where g.id = t.in_acc;
        debit  := case when v_ded > 0 then v_ded else 0 end;
        credit := case when v_ded > 0 then 0 else -v_ded end;
        line_role := 'tax';
        return next;
      end if;
      if v_signed - v_ded <> 0 then
        v_n := v_n + 1;
        line_no := v_n; gl_account_id := t.first_acc;
        select g.account_no, g.name into account_no, account_name from erp.gl_accounts g where g.id = t.first_acc;
        debit  := case when v_signed - v_ded > 0 then v_signed - v_ded else 0 end;
        credit := case when v_signed - v_ded > 0 then 0 else v_ded - v_signed end;
        line_role := 'tax_nd';
        return next;
      end if;
    else
      -- Cuota normal (o no deducible: comerciante en recargo de equivalencia → mayor coste, a la cuenta de la compra)
      v_side_acc := case when v_nd then t.first_acc when v_type = 'purchase' then t.in_acc else t.out_acc end;
      v_n := v_n + 1;
      line_no := v_n; gl_account_id := v_side_acc;
      select g.account_no, g.name into account_no, account_name from erp.gl_accounts g where g.id = v_side_acc;
      debit  := case when (v_type = 'purchase') = (v_signed > 0) then abs(v_signed) else 0 end;
      credit := case when (v_type = 'purchase') = (v_signed > 0) then 0 else abs(v_signed) end;
      line_role := case when v_nd then 'tax_nd' else 'tax' end;
      return next;
    end if;

    -- Recargo de equivalencia: lo cobra el mayorista al minorista (477 recargo) y el minorista lo paga sin deducirlo
    if t.re_pct is not null and (v_nd or (v_type = 'sale' and v_partner.equivalence_surcharge)) then
      v_re := round(t.base * t.re_pct / 100, 2);
      if v_re <> 0 then
        v_total := v_total + v_re;
        v_side_acc := case when v_nd then t.first_acc else t.re_acc end;
        v_n := v_n + 1;
        line_no := v_n; gl_account_id := v_side_acc;
        select g.account_no, g.name into account_no, account_name from erp.gl_accounts g where g.id = v_side_acc;
        debit  := case when (v_type = 'purchase') = (v_re > 0) then abs(v_re) else 0 end;
        credit := case when (v_type = 'purchase') = (v_re > 0) then 0 else abs(v_re) end;
        line_role := case when v_nd then 'surcharge_nd' else 'surcharge' end;
        return next;
      end if;
    end if;
  end loop;

  -- 3) Retención IRPF sobre la base imponible (sin el impuesto):
  --    compras → 4751 al HABER (la empresa la retiene y la ingresa en Hacienda: modelos 111 / 115)
  --    ventas  → 473 al DEBE (el cliente nos la retiene: es un pago a cuenta de nuestro impuesto)
  if v_wh_code is not null then
    v_wh_amt := round(v_base_total * v_wh.rate_pct / 100, 2);
    if v_wh_amt <> 0 then
      v_n := v_n + 1;
      line_no := v_n;
      gl_account_id := case v_type when 'purchase' then v_whs.payable_account_id else v_whs.receivable_account_id end;
      select g.account_no, g.name into account_no, account_name from erp.gl_accounts g
      where g.id = case v_type when 'purchase' then v_whs.payable_account_id else v_whs.receivable_account_id end;
      debit  := case when (v_type = 'purchase') = (v_wh_amt > 0) then 0 else abs(v_wh_amt) end;
      credit := case when (v_type = 'purchase') = (v_wh_amt > 0) then abs(v_wh_amt) else 0 end;
      tax_code := v_wh_code; tax_base := v_base_total; line_role := 'withholding';
      src_line := null; amount := null; sign := null; description := null;
      return next;
    end if;
  end if;

  -- 4) Tercero: lado contrario, por el total menos la retención (lo que realmente se paga o se cobra)
  if v_total = 0 then
    raise exception 'The invoice total is zero';
  end if;
  if v_kind = 'invoice' and v_total < 0 then
    raise exception 'The invoice total is negative: register it as a credit memo';
  end if;
  v_n := v_n + 1;
  line_no := v_n; gl_account_id := v_pacc.id; account_no := v_pacc.account_no; account_name := v_pacc.name;
  debit  := case when (v_type = 'purchase') = (v_total - v_wh_amt > 0) then 0 else abs(v_total - v_wh_amt) end;
  credit := case when (v_type = 'purchase') = (v_total - v_wh_amt > 0) then abs(v_total - v_wh_amt) else 0 end;
  tax_code := null; tax_base := null; line_role := 'partner';
  src_line := null; amount := null; sign := null; description := null;
  return next;
end $function$
;;

-- ---------------------------------------------------------------------
-- 9) Vista para la web: cada activo con su amortización contabilizada y su valor neto contable
-- ---------------------------------------------------------------------
create or replace view erp.v_fixed_assets with (security_invoker = true) as
select a.id, a.company_id, a.code, a.name, a.class_code, c.name as class_name, c.name_en as class_name_en, c.max_pct,
       ga.account_no as asset_account_no, ga.name as asset_account_name,
       gd.account_no as depreciation_account_no, ge.account_no as expense_account_no,
       a.acquisition_date, a.start_date, a.cost, a.residual_value, a.useful_life_months,
       round(1200.0 / a.useful_life_months, 2) as annual_pct,
       coalesce(d.posted, 0) as accumulated, a.cost - coalesce(d.posted, 0) as net_book_value, d.last_period,
       a.status, a.disposal_date, a.disposal_price,
       i.invoice_no, i.external_document_no, ie.entry_no as invoice_entry_no, fy.year as invoice_year,
       di.invoice_no as disposal_invoice_no, de.entry_no as disposal_entry_no, dfy.year as disposal_year
from erp.fixed_assets a
join erp.gl_accounts ga on ga.id = a.asset_account_id
join erp.gl_accounts gd on gd.id = a.depreciation_account_id
join erp.gl_accounts ge on ge.id = a.expense_account_id
left join erp.depreciation_classes c on c.code = a.class_code
left join lateral (select sum(x.amount) as posted, max(x.period_end) as last_period
                   from erp.asset_depreciations x where x.asset_id = a.id) d on true
left join erp.invoices i on i.id = a.invoice_id
left join erp.journal_entries ie on ie.id = i.entry_id
left join erp.fiscal_years fy on fy.id = ie.fiscal_year_id
left join erp.invoices di on di.id = a.disposal_invoice_id
left join erp.journal_entries de on de.id = a.disposal_entry_id
left join erp.fiscal_years dfy on dfy.id = de.fiscal_year_id;

revoke all on erp.v_fixed_assets from anon, public;
grant select on erp.v_fixed_assets to authenticated;
revoke execute on function erp.asset_accumulated_at(numeric, numeric, int, date, date), erp.depreciation_schedule(uuid),
  erp.asset_posted(uuid), erp.asset_account_pair(uuid, text, text), erp.asset_result_account(uuid, text, numeric),
  erp.create_fixed_asset(jsonb), erp.post_depreciation(uuid, date), erp.cancel_depreciation(uuid, date),
  erp.dispose_asset(jsonb), erp.cancel_disposal(uuid, date), erp.tg_entry_asset_reverse() from anon, public;
grant execute on function erp.asset_accumulated_at(numeric, numeric, int, date, date), erp.depreciation_schedule(uuid),
  erp.asset_posted(uuid), erp.create_fixed_asset(jsonb), erp.post_depreciation(uuid, date), erp.cancel_depreciation(uuid, date),
  erp.dispose_asset(jsonb), erp.cancel_disposal(uuid, date) to authenticated;
