-- =====================================================================
-- 0046 · FIN DE EJERCICIO II (2): deterioro del inmovilizado y rectificativas de compra de activos · v0.37.0
-- ---------------------------------------------------------------------
-- NRV 2.ª 2.2 del PGC 2007: al cierre, si el VALOR RECUPERABLE de un activo es menor que su valor neto contable, se
-- reconoce un DETERIORO; si después se recupera, se revierte, como mucho hasta el valor que tendría sin el deterioro.
--   · deterioro:  69x D / 29x H   (690 / 290 intangible · 691 / 291 material · 692 / 292 inversiones inmobiliarias)
--   · reversión:  29x D / 79x H
--   · las amortizaciones siguientes se calculan sobre el nuevo valor neto en la vida útil que queda (NRV 2.ª 2.2)
--   · en la baja, el deterioro acumulado se cancela con el resto (29x D) y entra en el resultado
-- RECTIFICATIVA de una compra de inmovilizado (rappel, descuento, devolución parcial): la línea a la cuenta del activo
-- baja su COSTE (NRV 2.ª 1.1) y la amortización pendiente se reparte en la vida útil que queda. Es el «hallazgo» de la
-- v0.35.0: antes bajaba la 21x pero no la ficha.
-- Las tres cosas son «sucesos» de la ficha (erp.asset_events): la amortización a una fecha se calcula por tramos
-- entre sucesos (erp.asset_depr_at). Sin sucesos da lo mismo que antes (erp.asset_accumulated_at). Re-ejecutable.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Sucesos de la ficha
-- ---------------------------------------------------------------------
create table if not exists erp.asset_events (
  id          uuid primary key default gen_random_uuid(),
  asset_id    uuid not null references erp.fixed_assets(id) on delete cascade,
  company_id  uuid not null references erp.companies(id) on delete cascade,
  kind        text not null check (kind in ('impairment', 'reversal', 'cost_adjustment')),
  event_date  date not null,
  amount      numeric(15,2) not null check (amount <> 0),       -- deterioro / reversión: > 0 · coste: el cambio (± )
  recoverable numeric(15,2),                                    -- valor recuperable estimado (deterioro / reversión)
  entry_id    uuid references erp.journal_entries(id),          -- deterioro / reversión
  invoice_id  uuid references erp.invoices(id),                 -- rectificativa
  created_at  timestamptz not null default now(),
  check ((kind = 'cost_adjustment') = (invoice_id is not null)),
  check (kind = 'cost_adjustment' or (amount > 0 and entry_id is not null))
);
comment on table erp.asset_events is 'Fixed asset events that change its depreciation: impairment (29x), its reversal and cost adjustments from credit memos.';
create index if not exists asset_events_asset_idx   on erp.asset_events (asset_id, event_date);
create index if not exists asset_events_company_idx on erp.asset_events (company_id);
create index if not exists asset_events_entry_idx   on erp.asset_events (entry_id);
create index if not exists asset_events_invoice_idx on erp.asset_events (invoice_id);
alter table erp.asset_events enable row level security;
drop policy if exists read on erp.asset_events;
create policy read on erp.asset_events for select to authenticated using (erp.can_read(company_id));
revoke all on erp.asset_events from anon, public;
grant select on erp.asset_events to authenticated;

-- ---------------------------------------------------------------------
-- 2) Cálculos: coste, deterioro y amortización acumulada a una fecha
-- ---------------------------------------------------------------------
-- Coste a una fecha (el de la ficha es el actual: le quitamos las rectificativas posteriores)
create or replace function erp.asset_cost_at(p_asset uuid, p_date date)
returns numeric language sql stable as $$
  select a.cost - coalesce((select sum(e.amount) from erp.asset_events e
                            where e.asset_id = a.id and e.kind = 'cost_adjustment' and e.event_date > p_date), 0)
  from erp.fixed_assets a where a.id = p_asset;
$$;

-- Deterioro neto acumulado a una fecha (deterioros − reversiones)
create or replace function erp.asset_impairment_at(p_asset uuid, p_date date)
returns numeric language sql stable as $$
  select coalesce(sum(case e.kind when 'impairment' then e.amount else -e.amount end), 0)
  from erp.asset_events e where e.asset_id = p_asset and e.kind in ('impairment', 'reversal') and e.event_date <= p_date;
$$;

-- Meses transcurridos desde la puesta en funcionamiento (el primer mes, por días), con 6 decimales
create or replace function erp.asset_months_at(p_life int, p_start date, p_date date)
returns numeric language sql immutable as $$
  select erp.asset_accumulated_at(p_life * 1000000.0, 0, p_life, p_start, p_date) / 1000000.0;
$$;

-- Amortización acumulada a una fecha, por tramos entre sucesos: en cada tramo, lo que queda por amortizar se reparte
-- en los meses de vida que quedan (NRV 2.ª 2.2). Sin sucesos, la regla de siempre.
create or replace function erp.asset_depr_at(p_asset uuid, p_date date)
returns numeric language plpgsql stable as $$
declare
  a      erp.fixed_assets;
  e      record;
  v_t    date;        -- inicio del tramo
  v_d    numeric;     -- amortizado al inicio del tramo
  v_rem  numeric;     -- lo que queda por amortizar al inicio del tramo
  v_at   numeric;
begin
  select * into a from erp.fixed_assets where id = p_asset;
  if not found or p_date < a.start_date then return 0; end if;
  if not exists (select 1 from erp.asset_events x where x.asset_id = a.id and x.event_date <= p_date) then
    return erp.asset_accumulated_at(erp.asset_cost_at(a.id, p_date), a.residual_value, a.useful_life_months, a.start_date, p_date);
  end if;
  v_t := a.start_date - 1; v_d := 0;      -- el día antes de empezar: 0 meses transcurridos
  v_rem := erp.asset_cost_at(a.id, a.start_date - 1) - a.residual_value;
  for e in select * from erp.asset_events x where x.asset_id = a.id and x.event_date <= p_date order by x.event_date, x.created_at loop
    v_at := erp.asset_tranche_at(a.useful_life_months, a.start_date, v_t, v_d, v_rem, e.event_date);
    v_rem := v_rem - (v_at - v_d)
             + case e.kind when 'impairment' then -e.amount when 'reversal' then e.amount else e.amount end;
    v_d := v_at; v_t := e.event_date;
  end loop;
  return erp.asset_tranche_at(a.useful_life_months, a.start_date, v_t, v_d, v_rem, p_date);
end $$;

-- Un tramo: amortizado al inicio (p_d) + lo que queda × meses del tramo / meses de vida que quedan
create or replace function erp.asset_tranche_at(p_life int, p_start date, p_from date, p_d numeric, p_rem numeric, p_date date)
returns numeric language sql immutable as $$
  select case when p_life - erp.asset_months_at(p_life, p_start, p_from) <= 0 or p_date <= p_from then p_d
              else p_d + least(greatest(p_rem, 0), round(greatest(p_rem, 0)
                     * (erp.asset_months_at(p_life, p_start, p_date) - erp.asset_months_at(p_life, p_start, p_from))
                     / (p_life - erp.asset_months_at(p_life, p_start, p_from)), 2)) end;
$$;

-- Valor neto contable a una fecha (con lo contabilizado y el deterioro)
create or replace function erp.asset_net_value_at(p_asset uuid, p_date date)
returns numeric language sql stable as $$
  select erp.asset_cost_at(p_asset, p_date)
       - coalesce((select sum(d.amount) from erp.asset_depreciations d where d.asset_id = p_asset and d.period_end <= p_date), 0)
       - erp.asset_impairment_at(p_asset, p_date);
$$;

-- Cuentas del deterioro: 2x → 29x (2917, 2918…), 69x (691) y 79x (791)
create or replace function erp.asset_impairment_account(p_company uuid, p_asset_no text, p_kind text)
returns uuid language plpgsql security definer set search_path = erp, public as $$
declare v_prefix text; v_name text;
begin
  v_prefix := case p_kind when 'allowance' then '29' || substr(p_asset_no, 2, 2)
                          when 'expense' then '69' || substr(p_asset_no, 2, 1) else '79' || substr(p_asset_no, 2, 1) end;
  v_name := case p_kind when 'allowance' then 'Deterioro de valor · ' || (select name from erp.gl_accounts where company_id = p_company and account_no = p_asset_no)
                        else (select t.name from erp.coa_template t where t.account_no = left(v_prefix, 3)) end;
  return erp.adjust_account(p_company, v_prefix, v_name);
end $$;

-- ---------------------------------------------------------------------
-- 3) Deterioro y su reversión
--   p: { asset_id, impairment_date, recoverable_value }   (o amount en vez del valor recuperable)
--   La amortización tiene que estar contabilizada hasta esa fecha: el deterioro compara con el valor neto de ese día.
-- ---------------------------------------------------------------------
create or replace function erp.asset_event_check(a erp.fixed_assets, p_date date)
returns void language plpgsql stable as $$
begin
  if a.status <> 'active' then raise exception 'Asset % is already disposed', a.code; end if;
  if p_date is null then raise exception 'The date is required'; end if;
  if p_date < a.start_date then raise exception 'The date cannot be earlier than the start date'; end if;
  if exists (select 1 from erp.asset_depreciations d where d.asset_id = a.id and d.period_end > p_date) then
    raise exception 'Asset % is already depreciated after %: cancel that depreciation first', a.code, p_date;
  end if;
  if exists (select 1 from erp.asset_events x where x.asset_id = a.id and x.event_date > p_date) then
    raise exception 'Asset % has a later impairment or adjustment', a.code;
  end if;
  if erp.asset_depr_at(a.id, p_date) - erp.asset_posted(a.id) > 0 then
    raise exception 'Post the depreciation of % up to % first', a.code, p_date;
  end if;
end $$;

create or replace function erp.impair_asset(p jsonb)
returns table (entry_no int, amount numeric, net_book_value numeric)
language plpgsql security definer set search_path = erp, public as $$
declare
  a       erp.fixed_assets;
  v_date  date := (p->>'impairment_date')::date;
  v_nbv   numeric;
  v_rec   numeric := round((p->>'recoverable_value')::numeric, 2);
  v_amt   numeric := round((p->>'amount')::numeric, 2);
  v_no    text;
  v_entry uuid;
  v_n     int;
begin
  select * into a from erp.fixed_assets where id = (p->>'asset_id')::uuid;
  if not found then raise exception 'Asset not found'; end if;
  if not erp.can_write(a.company_id) then raise exception 'No permission to register fixed assets in this company'; end if;
  perform erp.asset_event_check(a, v_date);
  v_nbv := erp.asset_net_value_at(a.id, v_date);
  if v_rec is not null then
    if v_rec < 0 then raise exception 'The recoverable value cannot be negative'; end if;
    v_amt := v_nbv - v_rec;
    if v_amt <= 0 then raise exception 'No impairment: the recoverable value (%) is not below the net book value (%)', v_rec, v_nbv; end if;
  end if;
  if v_amt is null or v_amt <= 0 then raise exception 'Give the recoverable value (or the impairment amount)'; end if;
  if v_amt > v_nbv then raise exception 'The impairment (%) cannot exceed the net book value (%)', v_amt, v_nbv; end if;
  v_no := (select account_no from erp.gl_accounts where id = a.asset_account_id);
  v_entry := erp.adjust_post(a.company_id, v_date, 'Deterioro de ' || a.code || ' · ' || a.name, null,
    erp.asset_impairment_account(a.company_id, v_no, 'expense'), erp.asset_impairment_account(a.company_id, v_no, 'allowance'), v_amt);
  insert into erp.asset_events (asset_id, company_id, kind, event_date, amount, recoverable, entry_id)
  values (a.id, a.company_id, 'impairment', v_date, v_amt, v_rec, v_entry);
  perform set_config('erp.asset_engine', 'on', true);
  v_n := erp.adjust_finish(v_entry);
  perform set_config('erp.asset_engine', 'off', true);
  entry_no := v_n; amount := v_amt; net_book_value := v_nbv - v_amt;
  return next;
end $$;

-- Reversión: como mucho hasta el valor neto que tendría sin deterioro (la amortización del plan original)
create or replace function erp.reverse_asset_impairment(p jsonb)
returns table (entry_no int, amount numeric, net_book_value numeric, capped boolean)
language plpgsql security definer set search_path = erp, public as $$
declare
  a       erp.fixed_assets;
  v_date  date := (p->>'reversal_date')::date;
  v_rec   numeric := round((p->>'recoverable_value')::numeric, 2);
  v_nbv   numeric;
  v_max   numeric;
  v_amt   numeric;
  v_no    text;
  v_entry uuid;
  v_n     int;
begin
  select * into a from erp.fixed_assets where id = (p->>'asset_id')::uuid;
  if not found then raise exception 'Asset not found'; end if;
  if not erp.can_write(a.company_id) then raise exception 'No permission to register fixed assets in this company'; end if;
  perform erp.asset_event_check(a, v_date);
  if erp.asset_impairment_at(a.id, v_date) <= 0 then raise exception 'Asset % has no impairment to reverse', a.code; end if;
  if v_rec is null or v_rec < 0 then raise exception 'Give the new recoverable value'; end if;
  v_nbv := erp.asset_net_value_at(a.id, v_date);
  -- valor neto sin deterioro: coste − la amortización del plan original a esa fecha
  v_max := least(erp.asset_impairment_at(a.id, v_date),
                 (erp.asset_cost_at(a.id, v_date) - erp.asset_accumulated_at(erp.asset_cost_at(a.id, v_date), a.residual_value,
                   a.useful_life_months, a.start_date, v_date)) - v_nbv);
  v_amt := least(v_rec - v_nbv, v_max);
  if v_amt <= 0 then raise exception 'No reversal: the recoverable value (%) is not above the net book value (%)', v_rec, v_nbv; end if;
  v_no := (select account_no from erp.gl_accounts where id = a.asset_account_id);
  v_entry := erp.adjust_post(a.company_id, v_date, 'Reversión del deterioro de ' || a.code || ' · ' || a.name, null,
    erp.asset_impairment_account(a.company_id, v_no, 'allowance'), erp.asset_impairment_account(a.company_id, v_no, 'reversal'), v_amt);
  insert into erp.asset_events (asset_id, company_id, kind, event_date, amount, recoverable, entry_id)
  values (a.id, a.company_id, 'reversal', v_date, v_amt, v_rec, v_entry);
  perform set_config('erp.asset_engine', 'on', true);
  v_n := erp.adjust_finish(v_entry);
  perform set_config('erp.asset_engine', 'off', true);
  entry_no := v_n; amount := v_amt; net_book_value := v_nbv + v_amt; capped := v_rec - v_nbv > v_max;
  return next;
end $$;

-- Deshacer el último deterioro o reversión (si no hay amortizaciones después)
create or replace function erp.cancel_asset_impairment(p_asset uuid, p_date date default null)
returns int language plpgsql security definer set search_path = erp, public as $$
declare a erp.fixed_assets; ev erp.asset_events; v_n int;
begin
  select * into a from erp.fixed_assets where id = p_asset;
  if not found then raise exception 'Asset not found'; end if;
  if not erp.can_write(a.company_id) then raise exception 'No permission to register fixed assets in this company'; end if;
  if a.status <> 'active' then raise exception 'Asset % is already disposed', a.code; end if;
  select * into ev from erp.asset_events x where x.asset_id = a.id order by x.event_date desc, x.created_at desc limit 1;
  if ev.id is null or ev.kind = 'cost_adjustment' then raise exception 'Asset % has no impairment to undo', a.code; end if;
  if exists (select 1 from erp.asset_depreciations d where d.asset_id = a.id and d.period_end > ev.event_date) then
    raise exception 'Asset % is already depreciated after %: cancel that depreciation first', a.code, ev.event_date;
  end if;
  perform set_config('erp.asset_engine', 'on', true);
  v_n := erp.adjust_reverse(ev.entry_id, coalesce(p_date, ev.event_date), 'Deterioro deshecho');
  perform set_config('erp.asset_engine', 'off', true);
  delete from erp.asset_events where id = ev.id;
  return v_n;
end $$;

-- ---------------------------------------------------------------------
-- 4) Rectificativa de una factura de compra de inmovilizado: ajusta el coste de la ficha
--    (cada línea de la rectificativa a la cuenta del activo de la factura original)
-- ---------------------------------------------------------------------
create or replace function erp.tg_invoice_line_asset_cost()
returns trigger language plpgsql security definer set search_path = erp, public as $$
declare v_inv erp.invoices; a erp.fixed_assets; v_delta numeric;
begin
  if coalesce(current_setting('erp.deleting_company', true), '') = 'on' then return new; end if;
  select * into v_inv from erp.invoices where id = new.invoice_id;
  if v_inv.document_kind <> 'credit_memo' or v_inv.invoice_type <> 'purchase' or v_inv.corrected_invoice_id is null then return new; end if;
  select * into a from erp.fixed_assets x
  where x.invoice_id = v_inv.corrected_invoice_id and x.asset_account_id = new.gl_account_id
  order by x.code limit 1;
  if not found then return new; end if;
  v_delta := round(new.amount * new.sign, 2);
  if a.status <> 'active' then raise exception 'Asset % is disposed: its purchase can no longer be credited', a.code; end if;
  if exists (select 1 from erp.asset_depreciations d where d.asset_id = a.id and d.period_end > v_inv.posting_date) then
    raise exception 'Asset % is already depreciated after %: cancel that depreciation first', a.code, v_inv.posting_date;
  end if;
  if exists (select 1 from erp.asset_events x where x.asset_id = a.id and x.event_date > v_inv.posting_date) then
    raise exception 'Asset % has a later impairment or adjustment', a.code;
  end if;
  if a.cost + v_delta <= a.residual_value then
    raise exception 'The credit memo leaves asset % without depreciable cost: retire it in Fixed assets instead', a.code;
  end if;
  insert into erp.asset_events (asset_id, company_id, kind, event_date, amount, invoice_id)
  values (a.id, a.company_id, 'cost_adjustment', v_inv.posting_date, v_delta, v_inv.id);
  update erp.fixed_assets set cost = cost + v_delta where id = a.id;
  return new;
end $$;
drop trigger if exists invoice_line_asset_cost on erp.invoice_lines;
create trigger invoice_line_asset_cost after insert on erp.invoice_lines
  for each row execute function erp.tg_invoice_line_asset_cost();

-- ---------------------------------------------------------------------
-- 5) Cuentas controladas: el deterioro del inmovilizado (290 / 291 / 292) lo mueve el módulo
-- ---------------------------------------------------------------------
insert into erp.control_rules (account_prefix, modules, side, note, note_en) values
('290', '{assets}', 'both', 'Deterioro del inmovilizado intangible: lo mueven el deterioro, su reversión y la baja del módulo de Inmovilizado.', 'Impairment of intangible assets: posted by Fixed assets.'),
('291', '{assets}', 'both', 'Deterioro del inmovilizado material: lo mueven el deterioro, su reversión y la baja del módulo de Inmovilizado.', 'Impairment of property, plant and equipment: posted by Fixed assets.'),
('292', '{assets}', 'both', 'Deterioro de las inversiones inmobiliarias: lo mueve el módulo de Inmovilizado.', 'Impairment of investment property: posted by Fixed assets.')
on conflict (account_prefix) do update set modules = excluded.modules, side = excluded.side, note = excluded.note, note_en = excluded.note_en;

-- ---------------------------------------------------------------------
-- 6) Versiones nuevas de funciones existentes (copiadas de la vigente): la amortización se calcula con
--    erp.asset_depr_at (por tramos) y la baja cancela el deterioro. Cambia solo lo marcado «v0.37.0».
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION erp.post_depreciation(p_company uuid, p_date date)
 RETURNS TABLE(entry_no integer, assets integer, amount numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
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
    select a.*, erp.asset_depr_at(a.id, p_date) - erp.asset_posted(a.id) as due
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
end $function$
;
;
CREATE OR REPLACE FUNCTION erp.dispose_asset(p jsonb)
 RETURNS TABLE(entry_no integer, net_book_value numeric, result numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
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
  v_imp    numeric;
begin
  select * into a from erp.fixed_assets where id = (p->>'asset_id')::uuid;
  if not found then raise exception 'Asset not found'; end if;
  if not erp.can_write(a.company_id) then raise exception 'No permission to register fixed assets in this company'; end if;
  if a.status <> 'active' then raise exception 'Asset % is already disposed', a.code; end if;
  if v_date is null then raise exception 'The disposal date is required'; end if;
  if v_date < a.start_date then raise exception 'The disposal date cannot be earlier than the start date'; end if;
  if exists (select 1 from erp.asset_events x where x.asset_id = a.id and x.event_date > v_date) then
    raise exception 'Asset % has a later impairment or adjustment', a.code;
  end if;
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

  v_catch := erp.asset_depr_at(a.id, v_date) - erp.asset_posted(a.id);
  v_acc := erp.asset_posted(a.id) + greatest(v_catch, 0);
  v_imp := erp.asset_impairment_at(a.id, v_date);                -- v0.37.0: deterioro acumulado
  v_nbv := a.cost - v_acc - v_imp;
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
  if v_imp > 0 then   -- v0.37.0: se cancela el deterioro acumulado (29x)
    insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description)
    values (v_entry, a.company_id, v_line + 1,
            erp.asset_impairment_account(a.company_id, (select account_no from erp.gl_accounts where id = a.asset_account_id), 'allowance'),
            v_imp, 0, 'Cancelación del deterioro');
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
end $function$
;
;
CREATE OR REPLACE FUNCTION erp.depreciation_schedule(p_asset uuid)
 RETURNS TABLE(year integer, amount numeric, accumulated numeric, net_book_value numeric)
 LANGUAGE sql
 STABLE
AS $function$
  with a as (select * from erp.fixed_assets where id = p_asset),
  y as (select generate_series(extract(year from a.start_date)::int,
                               extract(year from (a.start_date + make_interval(months => a.useful_life_months)))::int) as yr from a),
  c as (select y.yr, erp.asset_depr_at(a.id, make_date(y.yr, 12, 31)) as acc
        from y cross join a)
  select c.yr, c.acc - coalesce(lag(c.acc) over (order by c.yr), 0), c.acc, erp.asset_cost_at(p_asset, make_date(c.yr, 12, 31)) - c.acc - erp.asset_impairment_at(p_asset, make_date(c.yr, 12, 31))
  from c
  where c.acc - coalesce((select c2.acc from c c2 where c2.yr = c.yr - 1), 0) > 0
  order by c.yr;
$function$
;
;
CREATE OR REPLACE FUNCTION erp.run_audit_checks(p_company uuid, p_year integer, p_to_date date DEFAULT NULL::date)
 RETURNS TABLE(code text, sort integer, area text, status text, title text, title_en text, why text, why_en text, fix text, fix_en text, screen text, book numeric, ledger numeric, difference numeric, items integer, details jsonb)
 LANGUAGE plpgsql
 STABLE
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
begin
  if v_type is null or v_to is null then return; end if;     -- empresa o ejercicio que no existe (o no se puede ver)

  for r in select * from erp.audit_checks c order by c.sort loop
    v_book := null; v_ledger := null; v_items := 0; v_det := '[]'; v_sev := r.severity;

    if r.code in ('vat_input', 'vat_output') then
      -- 472 al Debe (soportado) · 477 al Haber (repercutido); sin liquidación ni prorrata
      v_prefix := case r.code when 'vat_input' then '472' else '477' end;
      v_sign   := case r.code when 'vat_input' then 1 else -1 end;
      select coalesce(sum(v_sign * (a.debit - a.credit)) filter (where a.source = 'invoice'), 0),
             coalesce(sum(v_sign * (a.debit - a.credit)), 0)
      into v_book, v_ledger
      from erp.audit_lines(p_company, p_year, v_to) a
      where a.account_no like v_prefix || '%' and a.source not in ('settlement', 'pro_rata');
      -- Detalle: asientos manuales o importados (cada uno junto con su contraasiento: si se anularon, no salen)
      with g as (
        select a.k, a.source, min(a.account_no) as account_no, sum(v_sign * (a.debit - a.credit)) as amount
        from erp.audit_lines(p_company, p_year, v_to) a
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
      -- Contabilidad: asientos que ABONAN la 4751 (las retenciones). Los que la cargan son el ingreso en Hacienda.
      -- Un contraasiento va con su original (por eso se agrupa por k y el signo es el del original).
      with g as (
        select a.k, a.source, min(a.account_no) as account_no, sum(a.credit - a.debit) as amount,
               (select sum(l.credit - l.debit) from erp.journal_lines l join erp.gl_accounts ga on ga.id = l.gl_account_id
                where l.entry_id = a.k and ga.account_no like '4751%') as original
        from erp.audit_lines(p_company, p_year, v_to) a
        where a.account_no like '4751%'
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
        from erp.audit_lines(p_company, p_year, v_to) a join erp.tax_codes c on c.code = a.tax_code
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
      with m as (
        select distinct a.entry_id, a.entry_no, a.posting_date
        from erp.audit_lines(p_company, p_year, v_to) a
        where a.source = 'manual' and a.entry_id = a.k
      ), h as (
        select m.*, erp.entry_controlled_lines(m.entry_id) as hit
        from m
        where not exists (select 1 from erp.journal_entries x
                          where x.reversal_of = m.entry_id and x.status = 'posted' and x.posting_date <= v_to)
          and not exists (select 1 from erp.payments py where py.entry_id = m.entry_id and py.linked)
      ), n as (
        select h.*, row_number() over (order by h.posting_date, h.entry_no) as rn
        from h where jsonb_array_length(h.hit) > 0
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('entry_id', n.entry_id, 'entry_no', n.entry_no, 'posting_date', n.posting_date,
                                                   'account_no', n.hit->0->>'account_no', 'modules', n.hit->0->'modules')
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
;
CREATE OR REPLACE FUNCTION erp.year_closing_preview(p_company uuid, p_year integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_fy       erp.fiscal_years;
  v_prev     erp.fiscal_years;
  v_next     erp.fiscal_years;
  v_done     erp.year_closings;
  v_checks   jsonb := '[]';
  v_n        int;
  v_txt      text;
  v_result   numeric;
  v_res_no   text := erp.result_account_no(p_company);
  v_pl       jsonb;
  v_close    jsonb;
begin
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;
  if not found then
    raise exception 'Fiscal year % does not exist', p_year;
  end if;
  select * into v_prev from erp.fiscal_years where company_id = p_company and year = p_year - 1;
  select * into v_next from erp.fiscal_years where company_id = p_company and year = p_year + 1;
  select * into v_done from erp.year_closings where fiscal_year_id = v_fy.id and status = 'posted';

  -- 1) COMPROBACIONES · error = impide cerrar · warning = hay que aceptarlo · info = solo informa
  if v_prev.id is not null and v_prev.status = 'open'
     and exists (select 1 from erp.journal_entries where fiscal_year_id = v_prev.id and status = 'posted') then
    v_checks := v_checks || jsonb_build_object('code', 'previous_year_open', 'severity', 'error', 'detail', p_year - 1);
  end if;

  select count(*) into v_n from erp.journal_entries where fiscal_year_id = v_fy.id and status = 'draft';
  if v_n > 0 then
    v_checks := v_checks || jsonb_build_object('code', 'draft_entries', 'severity', 'error', 'detail', v_n);
  end if;

  -- Trimestres de IVA / IGIC sin liquidar (después del cierre ya no se podrán contabilizar)
  select string_agg(x.tax || ' ' || x.q || 'T', ', ' order by x.tax, x.q) into v_txt
  from (select case s.tax_type when 'VAT' then 'IVA' else 'IGIC' end as tax, q
        from erp.tax_settlement_setup s cross join generate_series(1, 4) q
        where s.company_id = p_company
          and not exists (select 1 from erp.tax_settlements t
                          where t.company_id = p_company and t.tax_type = s.tax_type
                            and t.year = p_year and t.quarter = q and t.status = 'posted')) x;
  if v_txt is not null then
    v_checks := v_checks || jsonb_build_object('code', 'unsettled_quarters', 'severity', 'warning', 'detail', v_txt);
  end if;

  -- Saldos anómalos graves (p. ej. caja acreedora): se arrastrarían al año siguiente
  select string_agg(a.account_no, ', ' order by a.account_no) into v_txt
  from erp.balance_anomalies(p_company, p_year) a where a.severity = 'error';
  if v_txt is not null then
    v_checks := v_checks || jsonb_build_object('code', 'anomalies', 'severity', 'warning', 'detail', v_txt);
  end if;

  -- v0.35.0 · Inmovilizado sin amortizar hasta el final del ejercicio (la amortización es un gasto del año: NRV 2.ª)
  select string_agg(a.code, ', ' order by a.code) into v_txt
  from erp.fixed_assets a
  where a.company_id = p_company and a.status = 'active' and a.start_date <= v_fy.ending_date
    and erp.asset_depr_at(a.id, v_fy.ending_date) > erp.asset_posted(a.id);
  if v_txt is not null then
    v_checks := v_checks || jsonb_build_object('code', 'assets_not_depreciated', 'severity', 'warning', 'detail', v_txt);
  end if;

  -- v0.36.0 · Periodificaciones de un ejercicio anterior sin revertir (el gasto o el ingreso se quedaría en el balance)
  select string_agg(a.code, ', ' order by a.code) into v_txt
  from erp.accruals a
  where a.company_id = p_company and a.status = 'active' and a.cutoff_date < v_fy.starting_date;
  if v_txt is not null then
    v_checks := v_checks || jsonb_build_object('code', 'accruals_unreversed', 'severity', 'warning', 'detail', v_txt);
  end if;

  if not exists (select 1 from erp.gl_accounts where company_id = p_company and account_no = v_res_no) then
    v_checks := v_checks || jsonb_build_object('code', 'result_account_created', 'severity', 'info', 'detail', v_res_no);
  end if;
  if v_next.id is null then
    v_checks := v_checks || jsonb_build_object('code', 'next_year_created', 'severity', 'info', 'detail', p_year + 1);
  elsif v_next.status = 'closed' then
    v_checks := v_checks || jsonb_build_object('code', 'next_year_closed', 'severity', 'error', 'detail', p_year + 1);
  end if;

  -- 2) REGULARIZACIÓN: cada cuenta de gastos e ingresos se salda al lado contrario; la diferencia, a la 129
  select -coalesce(sum(b.balance), 0),
         coalesce(jsonb_agg(jsonb_build_object('account_no', b.account_no, 'account_name', b.account_name,
                    'debit', greatest(-b.balance, 0), 'credit', greatest(b.balance, 0)) order by b.account_no), '[]')
    into v_result, v_pl
  from erp.year_account_balances(v_fy.id) b
  where left(b.account_no, 1) in ('6', '7');
  if v_result <> 0 then
    v_pl := v_pl || jsonb_build_object('account_no', v_res_no, 'account_name', 'Resultado del ejercicio',
                      'debit', greatest(-v_result, 0), 'credit', greatest(v_result, 0));
  end if;

  -- 3) CIERRE: saldos de balance (grupos 1 a 5) después de la regularización, saldados al lado contrario
  select coalesce(jsonb_agg(jsonb_build_object('account_no', c.account_no, 'account_name', c.account_name,
                    'debit', greatest(-c.balance, 0), 'credit', greatest(c.balance, 0)) order by c.account_no), '[]')
    into v_close
  from (
    select b.account_no, b.account_name,
           b.balance + case when b.account_no = v_res_no then -v_result else 0 end as balance
    from erp.year_account_balances(v_fy.id) b
    where left(b.account_no, 1) between '1' and '5'
    union all   -- la 129 aún sin movimientos
    select v_res_no, 'Resultado del ejercicio', -v_result
    where v_result <> 0
      and not exists (select 1 from erp.year_account_balances(v_fy.id) b where b.account_no = v_res_no)
  ) c
  where c.balance <> 0;

  return jsonb_build_object(
    'year', p_year, 'status', v_fy.status,
    'closing_date', v_fy.ending_date, 'opening_date', v_fy.ending_date + 1,
    'checks', v_checks,
    'can_close', v_fy.status = 'open' and not exists (select 1 from jsonb_array_elements(v_checks) c where c->>'severity' = 'error'),
    'has_warnings', exists (select 1 from jsonb_array_elements(v_checks) c where c->>'severity' = 'warning'),
    'result', coalesce(v_done.result, v_result),
    'result_account_no', v_res_no,
    'closing_pl_lines', v_pl,
    'closing_lines', v_close,
    'closed', v_done.id is not null,
    'closing_id', v_done.id,
    'entries', case when v_done.id is null then null else jsonb_build_object(
       'closing_pl', (select entry_no from erp.journal_entries where id = v_done.closing_pl_entry_id),
       'closing',    (select entry_no from erp.journal_entries where id = v_done.closing_entry_id),
       'opening',    (select entry_no from erp.journal_entries where id = v_done.opening_entry_id)) end,
    'can_reopen', v_done.id is not null and coalesce(v_next.status, 'open') = 'open');
end $function$
;
;
CREATE OR REPLACE FUNCTION erp.tg_entry_asset_reverse()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.reversal_of is not null and coalesce(current_setting('erp.asset_engine', true), '') <> 'on'
     and (exists (select 1 from erp.asset_depreciations where entry_id = new.reversal_of)
          or exists (select 1 from erp.fixed_assets where disposal_entry_id = new.reversal_of)
          or exists (select 1 from erp.asset_events where entry_id = new.reversal_of)) then
    raise exception 'This entry belongs to the fixed assets module: cancel it from Fixed assets';
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
  from erp.journal_entries e where e.id = p_entry;
$function$
;
;
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

create or replace view erp.v_fixed_assets with (security_invoker = true) as
select a.id, a.company_id, a.code, a.name, a.class_code, c.name as class_name, c.name_en as class_name_en, c.max_pct,
       ga.account_no as asset_account_no, ga.name as asset_account_name,
       gd.account_no as depreciation_account_no, ge.account_no as expense_account_no,
       a.acquisition_date, a.start_date, a.cost, a.residual_value, a.useful_life_months,
       round(1200.0 / a.useful_life_months, 2) as annual_pct,
       coalesce(d.posted, 0) as accumulated, a.cost - coalesce(d.posted, 0) - erp.asset_impairment_at(a.id, 'infinity') as net_book_value, d.last_period,
       a.status, a.disposal_date, a.disposal_price,
       i.invoice_no, i.external_document_no, ie.entry_no as invoice_entry_no, fy.year as invoice_year,
       di.invoice_no as disposal_invoice_no, de.entry_no as disposal_entry_no, dfy.year as disposal_year,
       erp.asset_impairment_at(a.id, 'infinity') as impairment,                                        -- v0.37.0
       (select coalesce(jsonb_agg(jsonb_build_object('kind', ev.kind, 'date', ev.event_date, 'amount', ev.amount,
                                                     'recoverable', ev.recoverable, 'entry_no', ee.entry_no, 'year', efy.year,
                                                     'invoice_no', coalesce(ei.external_document_no, ei.invoice_no))
                                  order by ev.event_date, ev.created_at), '[]')
        from erp.asset_events ev left join erp.journal_entries ee on ee.id = ev.entry_id
        left join erp.fiscal_years efy on efy.id = ee.fiscal_year_id left join erp.invoices ei on ei.id = ev.invoice_id
        where ev.asset_id = a.id) as events
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

-- ---------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------
revoke execute on function erp.asset_impairment_account(uuid, text, text), erp.tg_invoice_line_asset_cost() from anon, public, authenticated;
revoke execute on function erp.asset_cost_at(uuid, date), erp.asset_impairment_at(uuid, date), erp.asset_months_at(int, date, date),
  erp.asset_depr_at(uuid, date), erp.asset_tranche_at(int, date, date, numeric, numeric, date), erp.asset_net_value_at(uuid, date),
  erp.asset_event_check(erp.fixed_assets, date), erp.impair_asset(jsonb), erp.reverse_asset_impairment(jsonb),
  erp.cancel_asset_impairment(uuid, date) from anon, public;
grant execute on function erp.asset_cost_at(uuid, date), erp.asset_impairment_at(uuid, date), erp.asset_months_at(int, date, date),
  erp.asset_depr_at(uuid, date), erp.asset_tranche_at(int, date, date, numeric, numeric, date), erp.asset_net_value_at(uuid, date),
  erp.asset_event_check(erp.fixed_assets, date), erp.impair_asset(jsonb), erp.reverse_asset_impairment(jsonb),
  erp.cancel_asset_impairment(uuid, date) to authenticated;
