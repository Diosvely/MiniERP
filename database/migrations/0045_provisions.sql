-- =====================================================================
-- 0045 · FIN DE EJERCICIO II (1): provisiones · v0.37.0
-- ---------------------------------------------------------------------
-- NRV 15.ª del PGC 2007: una PROVISIÓN es una obligación presente (legal, contractual o implícita) que nace de un
-- suceso pasado, cuya cancelación es probable y cuyo importe o fecha son inciertos. Se registra por la mejor estimación
-- y se REVISA en cada cierre (como las «provisiones» de SAP o los asientos periódicos de BC, pero con su ficha):
--
--   tipo            largo plazo   corto plazo   dotación (gasto por naturaleza)          exceso
--   impuestos       141           5292          633 / 631 / 669 / 678… (se elige)         7952
--   responsab.      142           5293          678 / 62x / 641… (se elige)               7953
--   comerciales     4999 (siempre corto plazo)  6959                                      7954
--
--   · DOTACIÓN:        gasto D / provisión H
--   · REVISIÓN:        más → gasto D / provisión H · menos → provisión D / 795x H (exceso)
--                      comerciales (garantías): se revierte TODA la del año anterior (4999 D / 7954 H) y se dota la nueva
--                      (6959 D / 4999 H), como dice el PGC para la 499
--   · RECLASIFICACIÓN: cuando vence en menos de un año, 141 / 142 → 5292 / 5293
--   · APLICACIÓN:      se paga: provisión D / 57x H; si se paga más, la diferencia al gasto; si menos, al exceso (795x)
-- Cuentas 141, 142, 5292, 5293 y 499 CONTROLADAS por el módulo. Re-ejecutable.
-- =====================================================================

-- 0) El PGC tiene la 633 / 638 (ajustes negativos / positivos en la imposición sobre beneficios): faltaban en la plantilla
insert into erp.coa_template (account_no, name, name_en, account_category) values
('633', 'Ajustes negativos en la imposición sobre beneficios', 'Negative adjustments to income tax', 'expense'),
('638', 'Ajustes positivos en la imposición sobre beneficios', 'Positive adjustments to income tax', 'expense')
on conflict (account_no) do nothing;

-- ---------------------------------------------------------------------
-- 1) Provisiones y sus movimientos
-- ---------------------------------------------------------------------
create table if not exists erp.provisions (
  id                    uuid primary key default gen_random_uuid(),
  company_id            uuid not null references erp.companies(id) on delete cascade,
  code                  text not null,
  kind                  text not null check (kind in ('taxes', 'liabilities', 'commercial')),
  term                  text not null check (term in ('long', 'short')),
  description           text not null,
  provision_account_id  uuid not null references erp.gl_accounts(id),   -- la de ahora (cambia al reclasificar)
  expense_account_id    uuid not null references erp.gl_accounts(id),
  excess_account_id     uuid not null references erp.gl_accounts(id),
  status                text not null default 'active' check (status in ('active', 'applied', 'cancelled')),
  created_at            timestamptz not null default now(),
  unique (company_id, code),
  check (kind <> 'commercial' or term = 'short')
);
comment on table erp.provisions is 'Provisions (PGC NRV 15.ª: 141 / 142 / 5292 / 5293 / 4999), reviewed at each year end.';
create index if not exists provisions_company_idx on erp.provisions (company_id);
create index if not exists provisions_prov_acc_idx on erp.provisions (provision_account_id);
create index if not exists provisions_exp_acc_idx  on erp.provisions (expense_account_id);
create index if not exists provisions_exc_acc_idx  on erp.provisions (excess_account_id);

create table if not exists erp.provision_movements (
  id              uuid primary key default gen_random_uuid(),
  provision_id    uuid not null references erp.provisions(id) on delete cascade,
  company_id      uuid not null references erp.companies(id) on delete cascade,
  seq             int not null,
  kind            text not null check (kind in ('allocation', 'revision', 'reclass', 'application')),
  movement_date   date not null,
  balance_before  numeric(15,2) not null,
  balance_after   numeric(15,2) not null check (balance_after >= 0),
  paid            numeric(15,2),                                       -- aplicación: lo pagado
  account_before  uuid references erp.gl_accounts(id),                 -- reclasificación: la cuenta de antes
  entry_id        uuid not null references erp.journal_entries(id),
  created_at      timestamptz not null default now(),
  unique (provision_id, seq)
);
create index if not exists provision_mov_company_idx on erp.provision_movements (company_id, movement_date);
create index if not exists provision_mov_entry_idx   on erp.provision_movements (entry_id);
create index if not exists provision_mov_acc_idx     on erp.provision_movements (account_before);

alter table erp.provisions enable row level security;
alter table erp.provision_movements enable row level security;
drop policy if exists read on erp.provisions;
drop policy if exists read on erp.provision_movements;
create policy read on erp.provisions for select to authenticated using (erp.can_read(company_id));
create policy read on erp.provision_movements for select to authenticated using (erp.can_read(company_id));
revoke all on erp.provisions, erp.provision_movements from anon, public;
grant select on erp.provisions, erp.provision_movements to authenticated;   -- se escriben con las funciones

-- Saldo de una provisión (el del último movimiento)
create or replace function erp.provision_balance(p_provision uuid)
returns numeric language sql stable as $$
  select coalesce((select m.balance_after from erp.provision_movements m where m.provision_id = p_provision
                   order by m.seq desc limit 1), 0);
$$;

-- Cuenta de la provisión según el tipo y el plazo
create or replace function erp.provision_prefix(p_kind text, p_term text)
returns text language sql immutable as $$
  select case p_kind when 'taxes' then case p_term when 'long' then '141' else '5292' end
                     when 'liabilities' then case p_term when 'long' then '142' else '5293' end
                     else '4999' end;
$$;

create or replace function erp.provision_account(p_company uuid, p_kind text, p_term text)
returns uuid language sql security definer set search_path = erp, public as $$
  select erp.adjust_account(p_company, erp.provision_prefix(p_kind, p_term), case erp.provision_prefix(p_kind, p_term)
    when '141' then 'Provisión para impuestos' when '142' then 'Provisión para otras responsabilidades'
    when '5292' then 'Provisión a corto plazo para impuestos' when '5293' then 'Provisión a corto plazo para otras responsabilidades'
    else 'Provisión para otras operaciones comerciales' end);
$$;

-- Asiento de un movimiento: líneas [(cuenta, debe, haber, texto)], lo contabiliza el motor de ajustes
create or replace function erp.provision_post(p_company uuid, p_date date, p_desc text, p_lines jsonb)
returns uuid language plpgsql security definer set search_path = erp, public as $$
declare v_entry uuid; x jsonb; n int := 0;
begin
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (p_company, erp.adjust_fiscal_year(p_company, p_date), p_date, left(p_desc, 250))
  returning id into v_entry;
  for x in select * from jsonb_array_elements(p_lines) loop
    if coalesce((x->>'debit')::numeric, 0) = 0 and coalesce((x->>'credit')::numeric, 0) = 0 then continue; end if;
    n := n + 1;
    insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description)
    values (v_entry, p_company, n, (x->>'account_id')::uuid, coalesce((x->>'debit')::numeric, 0), coalesce((x->>'credit')::numeric, 0), x->>'text');
  end loop;
  return v_entry;
end $$;

create or replace function erp.provision_add_movement(p erp.provisions, p_kind text, p_date date, p_before numeric, p_after numeric,
                                                       p_entry uuid, p_paid numeric default null, p_account_before uuid default null)
returns int language plpgsql security definer set search_path = erp, public as $$
begin
  if exists (select 1 from erp.provision_movements m where m.provision_id = p.id and m.movement_date > p_date) then
    raise exception 'Provision % already has a movement after %', p.code, p_date;
  end if;
  insert into erp.provision_movements (provision_id, company_id, seq, kind, movement_date, balance_before, balance_after, paid, account_before, entry_id)
  values (p.id, p.company_id, coalesce((select max(seq) from erp.provision_movements where provision_id = p.id), 0) + 1,
          p_kind, p_date, p_before, p_after, p_paid, p_account_before, p_entry);
  return erp.adjust_finish(p_entry);
end $$;

-- ---------------------------------------------------------------------
-- 2) Dotar una provisión
--   p: { company_id, kind: taxes | liabilities | commercial, term: long | short, description, amount, provision_date,
--        expense_account_no (impuestos y responsabilidades; las comerciales van a la 6959) }
-- ---------------------------------------------------------------------
create or replace function erp.create_provision(p jsonb)
returns table (provision_id uuid, code text, entry_no int)
language plpgsql security definer set search_path = erp, public as $$
declare
  v_company uuid := (p->>'company_id')::uuid;
  v_kind    text := p->>'kind';
  v_term    text := case when p->>'kind' = 'commercial' then 'short' else coalesce(p->>'term', 'long') end;
  v_date    date := (p->>'provision_date')::date;
  v_amount  numeric := round((p->>'amount')::numeric, 2);
  v_desc    text := btrim(coalesce(p->>'description', ''));
  v_exp     erp.gl_accounts;
  v_prov    erp.provisions;
  v_code    text;
  v_entry   uuid;
  v_no      int;
begin
  if not erp.can_write(v_company) then raise exception 'No permission to register provisions in this company'; end if;
  if v_kind is null or v_kind not in ('taxes', 'liabilities', 'commercial') then raise exception 'Invalid provision type: %', v_kind; end if;
  if v_term not in ('long', 'short') then raise exception 'Invalid provision term: %', v_term; end if;
  if v_desc = '' then raise exception 'The provision needs a description'; end if;
  if v_date is null then raise exception 'The provision date is required'; end if;
  if v_amount is null or v_amount <= 0 then raise exception 'The amount must be greater than zero'; end if;

  if v_kind = 'commercial' then
    v_entry := erp.adjust_account(v_company, '6959', 'Dotación a la provisión para otras operaciones comerciales');
    select * into v_exp from erp.gl_accounts where id = v_entry;   -- (la función, fuera del where: crea la cuenta)
  else
    select * into v_exp from erp.gl_accounts
    where company_id = v_company and account_no = p->>'expense_account_no' and account_type = 'posting';
    if not found or left(v_exp.account_no, 1) <> '6' or left(v_exp.account_no, 2) in ('68', '69') then
      raise exception 'Choose the expense account by nature (group 6, not 68 or 69)';
    end if;
  end if;

  select 'PRV-' || lpad((count(*) + 1)::text, 4, '0') into v_code from erp.provisions x where x.company_id = v_company;
  insert into erp.provisions (company_id, code, kind, term, description, provision_account_id, expense_account_id, excess_account_id)
  values (v_company, v_code, v_kind, v_term, v_desc, erp.provision_account(v_company, v_kind, v_term), v_exp.id,
          erp.adjust_account(v_company, case v_kind when 'taxes' then '7952' when 'liabilities' then '7953' else '7954' end,
            case v_kind when 'taxes' then 'Exceso de provisión para impuestos' when 'liabilities' then 'Exceso de provisión para otras responsabilidades'
                        else 'Exceso de provisión por operaciones comerciales' end))
  returning * into v_prov;
  v_entry := erp.provision_post(v_company, v_date, 'Provisión ' || v_code || ' · ' || v_desc, jsonb_build_array(
    jsonb_build_object('account_id', v_exp.id, 'debit', v_amount, 'text', 'Dotación'),
    jsonb_build_object('account_id', v_prov.provision_account_id, 'credit', v_amount, 'text', 'Dotación')));
  v_no := erp.provision_add_movement(v_prov, 'allocation', v_date, 0, v_amount, v_entry);
  provision_id := v_prov.id; code := v_code; entry_no := v_no;
  return next;
end $$;

-- ---------------------------------------------------------------------
-- 3) Revisar (nueva estimación al cierre)
--   p: { provision_id, review_date, new_amount }
-- ---------------------------------------------------------------------
create or replace function erp.revise_provision(p jsonb)
returns table (entry_no int, difference numeric)
language plpgsql security definer set search_path = erp, public as $$
declare
  v       erp.provisions;
  v_date  date := (p->>'review_date')::date;
  v_new   numeric := round((p->>'new_amount')::numeric, 2);
  v_old   numeric;
  v_entry uuid;
  v_lines jsonb;
begin
  select * into v from erp.provisions where id = (p->>'provision_id')::uuid;
  if not found then raise exception 'Provision not found'; end if;
  if not erp.can_write(v.company_id) then raise exception 'No permission to register provisions in this company'; end if;
  if v.status <> 'active' then raise exception 'Provision % is not active', v.code; end if;
  if v_date is null then raise exception 'The review date is required'; end if;
  if v_new is null or v_new < 0 then raise exception 'The new estimate cannot be negative'; end if;
  v_old := erp.provision_balance(v.id);
  if v.kind = 'commercial' then
    -- PGC (499): se abona la del año por la dotación (6959) y se carga la anterior por el exceso (7954)
    v_lines := jsonb_build_array(
      jsonb_build_object('account_id', v.provision_account_id, 'debit', v_old, 'text', 'Exceso de la estimación anterior'),
      jsonb_build_object('account_id', v.excess_account_id, 'credit', v_old, 'text', 'Exceso de la estimación anterior'),
      jsonb_build_object('account_id', v.expense_account_id, 'debit', v_new, 'text', 'Dotación del ejercicio'),
      jsonb_build_object('account_id', v.provision_account_id, 'credit', v_new, 'text', 'Dotación del ejercicio'));
  elsif v_new = v_old then
    raise exception 'The new estimate is the same as the current one (%)', v_old;
  elsif v_new > v_old then
    v_lines := jsonb_build_array(
      jsonb_build_object('account_id', v.expense_account_id, 'debit', v_new - v_old, 'text', 'Aumento de la estimación'),
      jsonb_build_object('account_id', v.provision_account_id, 'credit', v_new - v_old, 'text', 'Aumento de la estimación'));
  else
    v_lines := jsonb_build_array(
      jsonb_build_object('account_id', v.provision_account_id, 'debit', v_old - v_new, 'text', 'Exceso de provisión'),
      jsonb_build_object('account_id', v.excess_account_id, 'credit', v_old - v_new, 'text', 'Exceso de provisión'));
  end if;
  if v.kind = 'commercial' and v_old = 0 and v_new = 0 then raise exception 'The new estimate is the same as the current one (%)', v_old; end if;
  v_entry := erp.provision_post(v.company_id, v_date, 'Revisión de la provisión ' || v.code || ' · ' || v.description, v_lines);
  entry_no := erp.provision_add_movement(v, 'revision', v_date, v_old, v_new, v_entry);
  difference := v_new - v_old;
  return next;
end $$;

-- ---------------------------------------------------------------------
-- 4) Reclasificar a corto plazo (vence en menos de un año): 141 → 5292 · 142 → 5293
-- ---------------------------------------------------------------------
create or replace function erp.reclassify_provision(p_provision uuid, p_date date)
returns int language plpgsql security definer set search_path = erp, public as $$
declare v erp.provisions; v_bal numeric; v_new uuid; v_entry uuid; v_no int;
begin
  select * into v from erp.provisions where id = p_provision;
  if not found then raise exception 'Provision not found'; end if;
  if not erp.can_write(v.company_id) then raise exception 'No permission to register provisions in this company'; end if;
  if v.status <> 'active' then raise exception 'Provision % is not active', v.code; end if;
  if v.term <> 'long' then raise exception 'Provision % is already short-term', v.code; end if;
  if p_date is null then raise exception 'The date is required'; end if;
  v_bal := erp.provision_balance(v.id);
  if v_bal <= 0 then raise exception 'Provision % has no balance to reclassify', v.code; end if;
  v_new := erp.provision_account(v.company_id, v.kind, 'short');
  v_entry := erp.provision_post(v.company_id, p_date, 'Reclasificación a corto plazo de la provisión ' || v.code, jsonb_build_array(
    jsonb_build_object('account_id', v.provision_account_id, 'debit', v_bal, 'text', 'Reclasificación a corto plazo'),
    jsonb_build_object('account_id', v_new, 'credit', v_bal, 'text', 'Reclasificación a corto plazo')));
  v_no := erp.provision_add_movement(v, 'reclass', p_date, v_bal, v_bal, v_entry, null, v.provision_account_id);
  update erp.provisions set term = 'short', provision_account_id = v_new where id = v.id;
  return v_no;
end $$;

-- ---------------------------------------------------------------------
-- 5) Aplicar (se cumple la obligación y se paga)
--   p: { provision_id, application_date, paid, cash_account_no }
-- ---------------------------------------------------------------------
create or replace function erp.apply_provision(p jsonb)
returns table (entry_no int, difference numeric)
language plpgsql security definer set search_path = erp, public as $$
declare
  v       erp.provisions;
  v_date  date := (p->>'application_date')::date;
  v_paid  numeric := round((p->>'paid')::numeric, 2);
  v_cash  erp.gl_accounts;
  v_bal   numeric;
  v_entry uuid;
begin
  select * into v from erp.provisions where id = (p->>'provision_id')::uuid;
  if not found then raise exception 'Provision not found'; end if;
  if not erp.can_write(v.company_id) then raise exception 'No permission to register provisions in this company'; end if;
  if v.status <> 'active' then raise exception 'Provision % is not active', v.code; end if;
  if v_date is null then raise exception 'The application date is required'; end if;
  if v_paid is null or v_paid < 0 then raise exception 'The amount paid cannot be negative'; end if;
  select * into v_cash from erp.gl_accounts
  where company_id = v.company_id and account_no = p->>'cash_account_no' and account_type = 'posting';
  if v_paid > 0 and (not found or left(v_cash.account_no, 2) <> '57') then raise exception 'Choose a cash or bank account (57)'; end if;
  v_bal := erp.provision_balance(v.id);
  v_entry := erp.provision_post(v.company_id, v_date, 'Aplicación de la provisión ' || v.code || ' · ' || v.description, jsonb_build_array(
    jsonb_build_object('account_id', v.provision_account_id, 'debit', v_bal, 'text', 'Aplicación de la provisión'),
    jsonb_build_object('account_id', v.expense_account_id, 'debit', greatest(v_paid - v_bal, 0), 'text', 'Pagado de más sobre lo provisionado'),
    jsonb_build_object('account_id', v_cash.id, 'credit', v_paid, 'text', 'Pago'),
    jsonb_build_object('account_id', v.excess_account_id, 'credit', greatest(v_bal - v_paid, 0), 'text', 'Exceso de provisión')));
  entry_no := erp.provision_add_movement(v, 'application', v_date, v_bal, 0, v_entry, v_paid);
  update erp.provisions set status = 'applied' where id = v.id;
  difference := v_paid - v_bal;
  return next;
end $$;

-- ---------------------------------------------------------------------
-- 6) Deshacer el último movimiento (contraasiento). Si era la dotación, la provisión queda anulada.
-- ---------------------------------------------------------------------
create or replace function erp.cancel_provision_movement(p_provision uuid, p_date date default null)
returns int language plpgsql security definer set search_path = erp, public as $$
declare v erp.provisions; m erp.provision_movements; v_no int;
begin
  select * into v from erp.provisions where id = p_provision;
  if not found then raise exception 'Provision not found'; end if;
  if not erp.can_write(v.company_id) then raise exception 'No permission to register provisions in this company'; end if;
  if v.status = 'cancelled' then raise exception 'Provision % is already cancelled', v.code; end if;
  select * into m from erp.provision_movements where provision_id = v.id order by seq desc limit 1;
  v_no := erp.adjust_reverse(m.entry_id, coalesce(p_date, m.movement_date), 'Movimiento de provisión deshecho');
  delete from erp.provision_movements where id = m.id;
  if m.kind = 'allocation' then
    update erp.provisions set status = 'cancelled' where id = v.id;
  elsif m.kind = 'application' then
    update erp.provisions set status = 'active' where id = v.id;
  elsif m.kind = 'reclass' then
    update erp.provisions set term = 'long', provision_account_id = m.account_before where id = v.id;
  end if;
  return v_no;
end $$;

-- ---------------------------------------------------------------------
-- 7) Cuentas controladas (0036): 141, 142, 5292, 5293 y 499 por Provisiones
-- ---------------------------------------------------------------------
insert into erp.control_rules (account_prefix, modules, side, note, note_en) values
('141',  '{provisions}', 'both', 'Provisión para impuestos: la mueven la dotación, la revisión y la aplicación del módulo de Provisiones.', 'Provision for taxes: posted by the Provisions module.'),
('142',  '{provisions}', 'both', 'Provisión para otras responsabilidades: la mueve el módulo de Provisiones.', 'Provision for other liabilities: posted by the Provisions module.'),
('5292', '{provisions}', 'both', 'Provisión a corto plazo para impuestos: la mueve el módulo de Provisiones.', 'Short-term provision for taxes: posted by the Provisions module.'),
('5293', '{provisions}', 'both', 'Provisión a corto plazo para otras responsabilidades: la mueve el módulo de Provisiones.', 'Short-term provision for other liabilities: posted by the Provisions module.'),
('499',  '{provisions}', 'both', 'Provisiones por operaciones comerciales: las mueve el módulo de Provisiones.', 'Provisions for trade operations: posted by the Provisions module.')
on conflict (account_prefix) do update set modules = excluded.modules, side = excluded.side, note = excluded.note, note_en = excluded.note_en;

-- ---------------------------------------------------------------------
-- 8) Lista para la web
-- ---------------------------------------------------------------------
create or replace view erp.v_provisions with (security_invoker = true) as
select pv.id, pv.company_id, pv.code, pv.kind, pv.term, pv.description, pv.status,
       pa.account_no as provision_account_no, pa.name as provision_account_name, ea.account_no as expense_account_no,
       xa.account_no as excess_account_no, erp.provision_balance(pv.id) as balance,
       (select min(m.movement_date) from erp.provision_movements m where m.provision_id = pv.id) as first_date,
       (select max(m.movement_date) from erp.provision_movements m where m.provision_id = pv.id) as last_date,
       (select coalesce(jsonb_agg(jsonb_build_object('seq', m.seq, 'kind', m.kind, 'date', m.movement_date, 'before', m.balance_before,
                                                     'after', m.balance_after, 'paid', m.paid, 'entry_no', e.entry_no, 'year', fy.year)
                                  order by m.seq), '[]')
        from erp.provision_movements m join erp.journal_entries e on e.id = m.entry_id join erp.fiscal_years fy on fy.id = e.fiscal_year_id
        where m.provision_id = pv.id) as movements
from erp.provisions pv
join erp.gl_accounts pa on pa.id = pv.provision_account_id
join erp.gl_accounts ea on ea.id = pv.expense_account_id
join erp.gl_accounts xa on xa.id = pv.excess_account_id;
revoke all on erp.v_provisions from anon, public;
grant select on erp.v_provisions to authenticated;

-- ---------------------------------------------------------------------
-- 9) Versiones nuevas de funciones existentes (copiadas de la vigente; cambia solo lo marcado «v0.37.0»)
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
     -- v0.36.0: periodificaciones y deterioros
     and not exists (select 1 from erp.accruals ac where e.id in (ac.entry_id, ac.reversal_entry_id))
     and not exists (select 1 from erp.receivable_impairments ri where e.id in (ri.entry_id, ri.end_entry_id))
     -- v0.37.0: provisiones
     and not exists (select 1 from erp.provision_movements pm where pm.entry_id = e.id)
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
              -- v0.37.0: provisiones
              when exists (select 1 from erp.provision_movements pm where pm.entry_id = coalesce(e.reversal_of, e.id)) then 'provision'
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
-- Permisos: solo las funciones públicas del módulo
-- ---------------------------------------------------------------------
revoke execute on function erp.provision_account(uuid, text, text), erp.provision_post(uuid, date, text, jsonb),
  erp.provision_add_movement(erp.provisions, text, date, numeric, numeric, uuid, numeric, uuid)
  from anon, public, authenticated;
revoke execute on function erp.provision_balance(uuid), erp.provision_prefix(text, text), erp.create_provision(jsonb),
  erp.revise_provision(jsonb), erp.reclassify_provision(uuid, date), erp.apply_provision(jsonb), erp.cancel_provision_movement(uuid, date)
  from anon, public;
grant execute on function erp.provision_balance(uuid), erp.provision_prefix(text, text), erp.create_provision(jsonb),
  erp.revise_provision(jsonb), erp.reclassify_provision(uuid, date), erp.apply_provision(jsonb), erp.cancel_provision_movement(uuid, date)
  to authenticated;
