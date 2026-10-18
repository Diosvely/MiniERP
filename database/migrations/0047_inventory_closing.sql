-- =====================================================================
-- 0047 · FIN DE EJERCICIO II (3): regularización de existencias y asistente de cierre · v0.37.0
-- ---------------------------------------------------------------------
-- EXISTENCIAS POR INVENTARIO (el método habitual de la pyme española: las compras van a la 600-602 durante el año y
-- al cierre se cuenta el almacén). Por cada cuenta de existencias (30-36), al inventario del cierre:
--   · se da de baja la existencia inicial:   61x / 71x D  ·  3x H   (lo que había)
--   · se da de alta la final (recuento):     3x D  ·  61x / 71x H  (lo que hay)
--     30 → 610 · 31 → 611 · 32 → 612 (aprovisionamientos)  ·  33 → 710 · 34 → 711 · 35 → 712 · 36 → 713 (productos)
--   · DETERIORO (NRV 10.ª 2.2: valor neto realizable menor que el coste): se revierte el del año anterior
--     (39x D / 793x H) y se dota el nuevo (693x D / 39x H), como hace el PGC con la 39
-- ASISTENTE DE CIERRE: erp.closing_checklist(empresa, año) da los pasos del cierre en orden, con su estado, como el
-- asistente de cierre de A3 / Sage o la lista de «Cierre del ejercicio» de BC.
-- Cuentas 30-36 y 39 CONTROLADAS por el módulo de existencias. Re-ejecutable.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Inventarios del cierre
-- ---------------------------------------------------------------------
create table if not exists erp.inventory_counts (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null references erp.companies(id) on delete cascade,
  fiscal_year_id  uuid not null references erp.fiscal_years(id) on delete cascade,
  count_date      date not null,
  entry_id        uuid not null references erp.journal_entries(id),
  status          text not null default 'posted' check (status in ('posted', 'cancelled')),
  cancel_entry_id uuid references erp.journal_entries(id),
  created_at      timestamptz not null default now()
);
comment on table erp.inventory_counts is 'Year-end physical inventory (periodic method): change in inventories 61x / 71x and impairment 39x.';
create unique index if not exists inventory_counts_one_per_year on erp.inventory_counts (fiscal_year_id) where status = 'posted';
create index if not exists inventory_counts_company_idx on erp.inventory_counts (company_id);
create index if not exists inventory_counts_entry_idx   on erp.inventory_counts (entry_id);
create index if not exists inventory_counts_cancel_idx  on erp.inventory_counts (cancel_entry_id);

create table if not exists erp.inventory_count_lines (
  count_id            uuid not null references erp.inventory_counts(id) on delete cascade,
  company_id          uuid not null references erp.companies(id) on delete cascade,
  stock_account_id    uuid not null references erp.gl_accounts(id),
  variation_account_id uuid not null references erp.gl_accounts(id),
  initial_value       numeric(15,2) not null,     -- saldo contable antes del recuento
  final_value         numeric(15,2) not null check (final_value >= 0),
  impairment          numeric(15,2) not null default 0 check (impairment >= 0),       -- deterioro nuevo (39x)
  prev_impairment     numeric(15,2) not null default 0,                               -- el del año anterior, revertido
  primary key (count_id, stock_account_id)
);
create index if not exists inventory_lines_company_idx on erp.inventory_count_lines (company_id);
create index if not exists inventory_lines_stock_idx   on erp.inventory_count_lines (stock_account_id);
create index if not exists inventory_lines_var_idx     on erp.inventory_count_lines (variation_account_id);

alter table erp.inventory_counts enable row level security;
alter table erp.inventory_count_lines enable row level security;
drop policy if exists read on erp.inventory_counts;
drop policy if exists read on erp.inventory_count_lines;
create policy read on erp.inventory_counts for select to authenticated using (erp.can_read(company_id));
create policy read on erp.inventory_count_lines for select to authenticated using (erp.can_read(company_id));
revoke all on erp.inventory_counts, erp.inventory_count_lines from anon, public;
grant select on erp.inventory_counts, erp.inventory_count_lines to authenticated;

-- Cuentas de la regularización según el grupo de la cuenta de existencias (30-36)
create or replace function erp.inventory_account(p_company uuid, p_stock_no text, p_kind text)
returns uuid language plpgsql security definer set search_path = erp, public as $$
declare d text := substr(p_stock_no, 2, 1); v_prefix text;
begin
  v_prefix := case p_kind
    when 'variation' then case when d in ('0', '1', '2') then '61' || d else '71' || (d::int - 3)::text end
    when 'allowance' then '39' || d
    when 'expense'   then '693' || case d when '0' then '1' when '1' then '2' when '2' then '3' else '0' end
    else                  '793' || case d when '0' then '1' when '1' then '2' when '2' then '3' else '0' end end;
  return erp.adjust_account(p_company, v_prefix,
    coalesce((select t.name from erp.coa_template t where t.account_no = v_prefix),
             (select t.name from erp.coa_template t where t.account_no = left(v_prefix, 3))));
end $$;

-- Saldo contable de una cuenta a una fecha dentro de su ejercicio (con la apertura; sin el cierre)
create or replace function erp.account_balance_in_year(p_account uuid, p_fy uuid, p_date date)
returns numeric language sql stable as $$
  select coalesce(sum(l.debit - l.credit), 0) from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id
  where l.gl_account_id = p_account and e.fiscal_year_id = p_fy and e.status = 'posted' and e.entry_type <> 'closing'
    and e.posting_date <= p_date;
$$;

-- Vista previa: cuentas de existencias con su saldo (lo que habría que dar de baja) y el deterioro del año anterior
create or replace function erp.inventory_preview(p_company uuid, p_date date)
returns table (account_no text, account_name text, initial_value numeric, prev_impairment numeric,
               variation_account_no text)
language sql stable as $$
  with fy as (select id from erp.fiscal_years where company_id = p_company and p_date between starting_date and ending_date)
  select g.account_no, g.name, erp.account_balance_in_year(g.id, fy.id, p_date),
         coalesce((select -erp.account_balance_in_year(a.id, fy.id, p_date) from erp.gl_accounts a
                   where a.company_id = p_company and a.account_type = 'posting' and a.account_no like '39' || substr(g.account_no, 2, 1) || '%'
                   limit 1), 0),
         case when substr(g.account_no, 2, 1) in ('0', '1', '2') then '61' || substr(g.account_no, 2, 1)
              else '71' || (substr(g.account_no, 2, 1)::int - 3)::text end
  from erp.gl_accounts g cross join fy
  where g.company_id = p_company and g.account_type = 'posting' and g.account_no ~ '^3[0-6]'
  order by g.account_no;
$$;

-- ---------------------------------------------------------------------
-- 2) Contabilizar el inventario del cierre
--   p: { company_id, count_date, lines: [{ account_no, final_value, impairment }] }
--   Hay que incluir todas las cuentas de existencias con saldo (aunque el recuento sea 0).
-- ---------------------------------------------------------------------
create or replace function erp.post_inventory(p jsonb)
returns table (count_id uuid, entry_no int, variation numeric)
language plpgsql security definer set search_path = erp, public as $$
declare
  v_company uuid := (p->>'company_id')::uuid;
  v_date    date := (p->>'count_date')::date;
  v_fy      uuid;
  v_entry   uuid;
  v_count   uuid;
  x         jsonb;
  g         erp.gl_accounts;
  v_init    numeric; v_final numeric; v_imp numeric; v_prev numeric;
  v_var     uuid; v_alw uuid;
  v_n       int := 0;
  v_total   numeric := 0;
  v_no      int;
  v_missing text;
begin
  if not erp.can_write(v_company) then raise exception 'No permission to register inventories in this company'; end if;
  if v_date is null then raise exception 'The count date is required'; end if;
  v_fy := erp.adjust_fiscal_year(v_company, v_date);
  if exists (select 1 from erp.inventory_counts c where c.fiscal_year_id = v_fy and c.status = 'posted') then
    raise exception 'The inventory of this fiscal year is already posted: undo it first';
  end if;
  if jsonb_array_length(coalesce(p->'lines', '[]')) = 0 then raise exception 'The inventory needs at least one stock account'; end if;
  -- todas las cuentas con saldo tienen que estar en el recuento
  select string_agg(i.account_no, ', ') into v_missing from erp.inventory_preview(v_company, v_date) i
  where i.initial_value <> 0 and i.account_no not in (select l->>'account_no' from jsonb_array_elements(p->'lines') l);
  if v_missing is not null then raise exception 'Include every stock account with a balance in the count: %', v_missing; end if;

  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (v_company, v_fy, v_date, 'Regularización de existencias al ' || to_char(v_date, 'DD/MM/YYYY'))
  returning id into v_entry;
  insert into erp.inventory_counts (company_id, fiscal_year_id, count_date, entry_id)
  values (v_company, v_fy, v_date, v_entry) returning id into v_count;

  for x in select * from jsonb_array_elements(p->'lines') loop
    select * into g from erp.gl_accounts
    where company_id = v_company and account_no = x->>'account_no' and account_type = 'posting';
    if not found or g.account_no !~ '^3[0-6]' then raise exception 'Account % is not a stock account (30-36)', x->>'account_no'; end if;
    v_final := round(coalesce((x->>'final_value')::numeric, 0), 2);
    v_imp := round(coalesce((x->>'impairment')::numeric, 0), 2);
    if v_final < 0 or v_imp < 0 then raise exception 'The count and the impairment cannot be negative'; end if;
    if v_imp > v_final then raise exception 'The impairment of % cannot exceed its value (%)', g.account_no, v_final; end if;
    v_init := erp.account_balance_in_year(g.id, v_fy, v_date);
    v_var := erp.inventory_account(v_company, g.account_no, 'variation');
    v_alw := erp.inventory_account(v_company, g.account_no, 'allowance');
    v_prev := -erp.account_balance_in_year(v_alw, v_fy, v_date);
    -- baja de la existencia inicial y alta de la final
    if v_init <> 0 then
      insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description) values
        (v_entry, v_company, v_n + 1, v_var, greatest(v_init, 0), greatest(-v_init, 0), 'Existencia inicial · ' || g.name),
        (v_entry, v_company, v_n + 2, g.id, greatest(-v_init, 0), greatest(v_init, 0), 'Existencia inicial · ' || g.name);
      v_n := v_n + 2;
    end if;
    if v_final > 0 then
      insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description) values
        (v_entry, v_company, v_n + 1, g.id, v_final, 0, 'Existencia final · ' || g.name),
        (v_entry, v_company, v_n + 2, v_var, 0, v_final, 'Existencia final · ' || g.name);
      v_n := v_n + 2;
    end if;
    -- deterioro: se revierte el anterior y se dota el nuevo
    if v_prev > 0 then
      insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description) values
        (v_entry, v_company, v_n + 1, v_alw, v_prev, 0, 'Reversión del deterioro anterior · ' || g.name),
        (v_entry, v_company, v_n + 2, erp.inventory_account(v_company, g.account_no, 'reversal'), 0, v_prev, 'Reversión del deterioro anterior · ' || g.name);
      v_n := v_n + 2;
    end if;
    if v_imp > 0 then
      insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description) values
        (v_entry, v_company, v_n + 1, erp.inventory_account(v_company, g.account_no, 'expense'), v_imp, 0, 'Deterioro · ' || g.name),
        (v_entry, v_company, v_n + 2, v_alw, 0, v_imp, 'Deterioro · ' || g.name);
      v_n := v_n + 2;
    end if;
    insert into erp.inventory_count_lines (count_id, company_id, stock_account_id, variation_account_id, initial_value, final_value, impairment, prev_impairment)
    values (v_count, v_company, g.id, v_var, v_init, v_final, v_imp, v_prev);
    v_total := v_total + v_final - v_init;
  end loop;
  if v_n = 0 then raise exception 'Nothing to post: every stock account is zero'; end if;
  v_no := erp.adjust_finish(v_entry);
  count_id := v_count; entry_no := v_no; variation := v_total;
  return next;
end $$;

-- Deshacer el inventario (contraasiento)
create or replace function erp.cancel_inventory(p_count uuid, p_date date default null)
returns int language plpgsql security definer set search_path = erp, public as $$
declare c erp.inventory_counts; v_no int;
begin
  select * into c from erp.inventory_counts where id = p_count;
  if not found then raise exception 'Inventory count not found'; end if;
  if not erp.can_write(c.company_id) then raise exception 'No permission to register inventories in this company'; end if;
  if c.status <> 'posted' then raise exception 'This inventory is already cancelled'; end if;
  v_no := erp.adjust_reverse(c.entry_id, coalesce(p_date, c.count_date), 'Inventario deshecho');
  update erp.inventory_counts set status = 'cancelled', cancel_entry_id = (select reversed_by from erp.journal_entries where id = c.entry_id)
  where id = c.id;
  return v_no;
end $$;

-- ---------------------------------------------------------------------
-- 3) Cuentas controladas: existencias (30-36) y su deterioro (39) por el módulo de existencias
-- ---------------------------------------------------------------------
insert into erp.control_rules (account_prefix, modules, side, note, note_en)
select p, '{inventory}', 'both',
       case when p = '39' then 'Deterioro de existencias: lo dota y lo revierte el inventario del cierre.'
            else 'Existencias: las mueve el inventario del cierre (las compras van a la 600-602).' end,
       case when p = '39' then 'Inventory impairment: posted by the year-end count.'
            else 'Inventories: posted by the year-end count (purchases go to 600-602).' end
from unnest(array['30', '31', '32', '33', '34', '35', '36', '39']) p
on conflict (account_prefix) do update set modules = excluded.modules, side = excluded.side, note = excluded.note, note_en = excluded.note_en;

-- ---------------------------------------------------------------------
-- 4) Asistente de cierre: los pasos en orden, con su estado
--    status: done (hecho) · pending (falta) · review (revísalo tú: el ERP no lo puede saber) · na (no aplica)
-- ---------------------------------------------------------------------
create or replace function erp.closing_checklist(p_company uuid, p_year int)
returns table (step int, code text, status text, detail jsonb, screen text)
language plpgsql stable as $$
declare
  v_fy    erp.fiscal_years;
  v_type  text := (select case c.tax_territory when 'canary_islands' then 'IGIC' else 'VAT' end from erp.companies c where c.id = p_company);
  v_n     int;
  v_m     int;
  v_txt   text;
begin
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;
  if not found or not erp.can_read(p_company) then return; end if;

  -- 1) Liquidaciones de IVA / IGIC de los cuatro trimestres
  select count(*) into v_n from erp.tax_settlements s
  where s.company_id = p_company and s.year = p_year and s.status = 'posted' and s.tax_type = v_type;
  select count(*) into v_m from erp.invoices i where i.company_id = p_company and i.fiscal_year_id = v_fy.id;
  step := 1; code := 'settlements'; screen := 'settlement';
  status := case when v_n >= 4 then 'done' when v_m = 0 and v_n = 0 then 'na' else 'pending' end;
  detail := jsonb_build_object('settled', v_n, 'tax', v_type); return next;

  -- 2) Periodificaciones del año anterior revertidas
  select count(*) into v_n from erp.accruals a where a.company_id = p_company and a.status = 'active' and a.cutoff_date < v_fy.starting_date;
  step := 2; code := 'accruals_reversed'; screen := 'adjustments';
  status := case when v_n = 0 then 'done' else 'pending' end; detail := jsonb_build_object('pending', v_n); return next;

  -- 3) Amortización del inmovilizado hasta el 31/12
  select count(*), count(*) filter (where erp.asset_depr_at(a.id, v_fy.ending_date) > erp.asset_posted(a.id)) into v_m, v_n
  from erp.fixed_assets a where a.company_id = p_company and a.status = 'active' and a.start_date <= v_fy.ending_date;
  step := 3; code := 'depreciation'; screen := 'assets';
  status := case when v_m = 0 then 'na' when v_n = 0 then 'done' else 'pending' end;
  detail := jsonb_build_object('assets', v_m, 'pending', v_n); return next;

  -- 4) Deterioro del inmovilizado: el valor recuperable lo estima la empresa
  step := 4; code := 'asset_impairment'; screen := 'assets';
  status := case when v_m = 0 then 'na' else 'review' end;
  detail := jsonb_build_object('impaired', (select count(distinct ev.asset_id) from erp.asset_events ev join erp.fixed_assets a on a.id = ev.asset_id
                                            where ev.company_id = p_company and ev.kind = 'impairment' and a.status = 'active')); return next;

  -- 5) Periodificaciones del cierre (las de este año)
  select count(*) into v_n from erp.accruals a where a.company_id = p_company and a.status <> 'cancelled'
    and a.cutoff_date between v_fy.starting_date and v_fy.ending_date;
  step := 5; code := 'accruals'; screen := 'adjustments';
  status := case when v_n > 0 then 'done' else 'review' end; detail := jsonb_build_object('accruals', v_n); return next;

  -- 6) Deterioro de clientes: vencidas hace más de 6 meses sin deterioro, y deterioros de facturas ya cobradas
  select count(*) into v_n from erp.open_items(p_company, v_fy.ending_date) o
  where o.invoice_type = 'sale' and o.pending > 0 and o.due_date + interval '6 months' <= v_fy.ending_date
    and not exists (select 1 from erp.receivable_impairments i where i.invoice_id = o.invoice_id and i.status = 'active');
  select count(*) into v_m from erp.receivable_impairments i join erp.open_items(p_company, v_fy.ending_date) o on o.invoice_id = i.invoice_id
  where i.company_id = p_company and i.status = 'active' and i.method = 'individual' and o.pending <= 0;
  step := 6; code := 'bad_debts'; screen := 'adjustments';
  status := case when v_m > 0 then 'pending' when v_n > 0 then 'review' else 'done' end;
  detail := jsonb_build_object('overdue_6m', v_n, 'collected', v_m); return next;

  -- 7) Provisiones revisadas este año
  select count(*), count(*) filter (where not exists (select 1 from erp.provision_movements m where m.provision_id = pv.id
                                                      and m.movement_date between v_fy.starting_date and v_fy.ending_date))
  into v_m, v_n from erp.provisions pv where pv.company_id = p_company and pv.status = 'active'
    and exists (select 1 from erp.provision_movements m where m.provision_id = pv.id and m.movement_date <= v_fy.ending_date);
  step := 7; code := 'provisions'; screen := 'adjustments';
  status := case when v_m = 0 then 'review' when v_n = 0 then 'done' else 'pending' end;
  detail := jsonb_build_object('active', v_m, 'not_reviewed', v_n); return next;

  -- 8) Inventario del cierre (si hay existencias o compras de aprovisionamientos)
  select count(*) into v_n from erp.inventory_counts c where c.fiscal_year_id = v_fy.id and c.status = 'posted';
  select count(*) into v_m from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id join erp.gl_accounts g on g.id = l.gl_account_id
  where e.fiscal_year_id = v_fy.id and e.status = 'posted' and (g.account_no ~ '^60[0-2]' or g.account_no ~ '^3[0-6]');
  step := 8; code := 'inventory'; screen := 'adjustments';
  status := case when v_n > 0 then 'done' when v_m = 0 then 'na' else 'pending' end;
  detail := jsonb_build_object('posted', v_n > 0); return next;

  -- 9) Comprobaciones del auditor sin avisos ni errores
  select count(*), string_agg(c.code, ', ' order by c.sort) into v_n, v_txt
  from erp.run_audit_checks(p_company, p_year, v_fy.ending_date) c where c.status in ('warning', 'error');
  step := 9; code := 'audit_checks'; screen := 'checks';
  status := case when v_n = 0 then 'done' else 'pending' end; detail := jsonb_build_object('open', v_n, 'codes', v_txt); return next;

  -- 10) Cierre del ejercicio (regularización, cierre y apertura)
  step := 10; code := 'close'; screen := 'closing';
  status := case when v_fy.status = 'closed' then 'done' else 'pending' end;
  detail := jsonb_build_object('fiscal_year_status', v_fy.status); return next;
end $$;

-- ---------------------------------------------------------------------
-- 5) Versiones nuevas de funciones existentes (copiadas de la vigente; cambia solo lo marcado «v0.37.0»)
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
revoke execute on function erp.inventory_account(uuid, text, text) from anon, public, authenticated;
revoke execute on function erp.account_balance_in_year(uuid, uuid, date), erp.inventory_preview(uuid, date), erp.post_inventory(jsonb),
  erp.cancel_inventory(uuid, date), erp.closing_checklist(uuid, int) from anon, public;
grant execute on function erp.account_balance_in_year(uuid, uuid, date), erp.inventory_preview(uuid, date), erp.post_inventory(jsonb),
  erp.cancel_inventory(uuid, date), erp.closing_checklist(uuid, int) to authenticated;
