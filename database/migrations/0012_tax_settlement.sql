-- =====================================================================
-- 0012 · TAX SETTLEMENT · Liquidación trimestral de IVA / IGIC (modelos 303 / 420)
-- ---------------------------------------------------------------------
-- Al cerrar el trimestre se saldan las cuentas de impuesto del periodo:
--     477 (repercutido)  −  472 (soportado)  −  cuotas a compensar de periodos anteriores
--     = positivo → 4750 Hacienda acreedora (a ingresar)
--     = negativo → 4700 Hacienda deudora (a compensar en los siguientes; o a devolver en el 4T)
--
-- Como "Calc. and Post VAT Settlement" de BC o el informe RFUMSV00 + traspaso de saldos de SAP.
--
--   erp.tax_settlement_calc(...)  → borrador: casillas por tipo, cuadre libro registro ↔ contabilidad y asiento
--   erp.post_tax_settlement(...)  → contabiliza el asiento y bloquea el trimestre
--   erp.cancel_tax_settlement(id) → deshace la última liquidación (contraasiento) para corregir el periodo
-- =====================================================================

create table erp.tax_settlements (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null references erp.companies(id) on delete cascade,
  tax_type         text not null check (tax_type in ('VAT', 'IGIC')),
  year             smallint not null,
  quarter          smallint not null check (quarter between 1 and 4),
  period_start     date not null,
  period_end       date not null,
  output_tax       numeric(15,2) not null,   -- cuotas devengadas (477)
  input_tax        numeric(15,2) not null,   -- cuotas deducibles (472)
  carry_applied    numeric(15,2) not null default 0,   -- compensado de periodos anteriores
  final_result     numeric(15,2) not null,   -- > 0 a ingresar · < 0 a compensar / devolver
  register_difference numeric(15,2) not null default 0,  -- contabilidad − libro registro (debería ser 0)
  outcome          text not null check (outcome in ('payable', 'carry_forward', 'refund', 'zero')),
  status           text not null default 'posted' check (status in ('posted', 'cancelled')),
  entry_id         uuid references erp.journal_entries(id),
  created_by       uuid default auth.uid(),
  created_at       timestamptz not null default now()
);
create unique index tax_settlements_unique_posted
  on erp.tax_settlements (company_id, tax_type, year, quarter) where status = 'posted';

-- Solo el motor crea o cancela liquidaciones
create or replace function erp.tg_tax_settlement_protect()
returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('erp.deleting_company', true), '') = 'on'
     or coalesce(current_setting('erp.tax_settlement_engine', true), '') = 'on' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  raise exception 'Tax settlements are created only with post_tax_settlement()';
end $$;

create trigger tax_settlement_protect before insert or update or delete on erp.tax_settlements
  for each row execute function erp.tg_tax_settlement_protect();

-- Fechas de un trimestre natural
create or replace function erp.quarter_start(p_year int, p_quarter int)
returns date language sql immutable as $$ select make_date(p_year, 3 * (p_quarter - 1) + 1, 1) $$;
create or replace function erp.quarter_end(p_year int, p_quarter int)
returns date language sql immutable as $$
  select (make_date(p_year, 3 * (p_quarter - 1) + 1, 1) + interval '3 months' - interval '1 day')::date
$$;

-- Asientos que NO cuentan como movimiento del periodo: las propias liquidaciones y sus anulaciones
create or replace function erp.is_settlement_entry(p_entry uuid)
returns boolean language sql stable as $$
  select exists (select 1 from erp.tax_settlements s
                 join erp.journal_entries e on e.id = p_entry
                 where s.entry_id = e.id or s.entry_id = e.reversal_of);
$$;

-- ---------------------------------------------------------------------
-- CÁLCULO (borrador). No guarda nada.
-- ---------------------------------------------------------------------
create or replace function erp.tax_settlement_calc(
  p_company uuid, p_tax_type text, p_year int, p_quarter int, p_refund boolean default false)
returns jsonb language plpgsql stable as $$
declare
  v_start    date := erp.quarter_start(p_year, p_quarter);
  v_end      date := erp.quarter_end(p_year, p_quarter);
  v_set      erp.tax_settlement_setup;
  v_out      numeric;
  v_in       numeric;
  v_reg_out  numeric;
  v_reg_in   numeric;
  v_carry    numeric;
  v_applied  numeric := 0;
  v_result   numeric;
  v_final    numeric;
  v_outcome  text;
  v_boxes    jsonb;
  v_lines    jsonb;
  v_done     erp.tax_settlements;
begin
  if p_quarter not between 1 and 4 then
    raise exception 'Invalid quarter: %', p_quarter;
  end if;
  select * into v_set from erp.tax_settlement_setup where company_id = p_company and tax_type = p_tax_type;
  if not found then
    raise exception '% is not set up for this company (Taxes tab)', p_tax_type;
  end if;
  select * into v_done from erp.tax_settlements
  where company_id = p_company and tax_type = p_tax_type and year = p_year and quarter = p_quarter and status = 'posted';

  -- 1) Movimiento del trimestre en las cuentas de impuesto (lo que dice la CONTABILIDAD)
  with acc as (
    select distinct s.output_account_id as id, 'output' as side from erp.tax_setup s
      join erp.tax_codes c on c.code = s.tax_code
      where s.company_id = p_company and c.tax_type = p_tax_type and s.output_account_id is not null
    union
    select distinct s.input_account_id, 'input' from erp.tax_setup s
      join erp.tax_codes c on c.code = s.tax_code
      where s.company_id = p_company and c.tax_type = p_tax_type and s.input_account_id is not null
  ), mov as (
    select acc.id, acc.side, g.account_no, g.name,
           coalesce(sum(l.debit - l.credit), 0) as balance   -- saldo deudor (+) / acreedor (−) del trimestre
    from acc
    join erp.gl_accounts g on g.id = acc.id
    left join erp.journal_lines l on l.gl_account_id = acc.id
      and exists (select 1 from erp.journal_entries e where e.id = l.entry_id and e.status = 'posted'
                  and e.posting_date between v_start and v_end and not erp.is_settlement_entry(e.id))
    group by acc.id, acc.side, g.account_no, g.name
  )
  select coalesce(sum(-balance) filter (where side = 'output'), 0),
         coalesce(sum(balance)  filter (where side = 'input'), 0),
         coalesce(jsonb_agg(jsonb_build_object('account_no', account_no, 'account_name', name,
                    -- se salda: un saldo deudor se cierra al Haber y uno acreedor al Debe
                    'debit', case when balance < 0 then -balance else 0 end,
                    'credit', case when balance > 0 then balance else 0 end) order by account_no)
                  filter (where balance <> 0), '[]'::jsonb)
    into v_out, v_in, v_lines
  from mov;

  -- 2) Casillas del borrador por tipo, desde el LIBRO REGISTRO de facturas
  select coalesce(jsonb_agg(jsonb_build_object('side', b.side, 'tax_code', b.tax_code, 'rate_pct', b.rate_pct,
                    'tax_base', b.base, 'tax_amount', b.amount) order by b.side desc, b.rate_pct), '[]'::jsonb),
         coalesce(sum(b.amount) filter (where b.side = 'output'), 0),
         coalesce(sum(b.amount) filter (where b.side = 'input'), 0)
    into v_boxes, v_reg_out, v_reg_in
  from (
    select case r.invoice_type when 'sale' then 'output' else 'input' end as side,
           r.tax_code, r.rate_pct, sum(r.tax_base) as base, sum(r.tax_amount) as amount
    from erp.v_invoice_register r
    where r.company_id = p_company and r.tax_type = p_tax_type and r.posting_date between v_start and v_end
    group by 1, 2, 3
  ) b;

  -- 3) Cuotas a compensar de periodos anteriores
  select coalesce(sum(case when outcome = 'carry_forward' then -final_result else 0 end), 0)
         - coalesce(sum(carry_applied), 0)
    into v_carry
  from erp.tax_settlements
  where company_id = p_company and tax_type = p_tax_type and status = 'posted'
    and (year, quarter) < (p_year, p_quarter);

  v_result := v_out - v_in;
  if v_result > 0 and v_carry > 0 then
    v_applied := least(v_result, v_carry);
  end if;
  v_final := v_result - v_applied;
  v_outcome := case when v_final > 0 then 'payable'
                    when v_final = 0 then 'zero'
                    when p_quarter = 4 and p_refund then 'refund'
                    else 'carry_forward' end;

  -- 4) Líneas de compensación y resultado
  if v_applied > 0 then
    v_lines := v_lines || jsonb_build_object('account_no', (select account_no from erp.gl_accounts where id = v_set.receivable_account_id),
      'account_name', (select name from erp.gl_accounts where id = v_set.receivable_account_id), 'debit', 0, 'credit', v_applied);
  end if;
  if v_final > 0 then
    v_lines := v_lines || jsonb_build_object('account_no', (select account_no from erp.gl_accounts where id = v_set.payable_account_id),
      'account_name', (select name from erp.gl_accounts where id = v_set.payable_account_id), 'debit', 0, 'credit', v_final);
  elsif v_final < 0 then
    v_lines := v_lines || jsonb_build_object('account_no', (select account_no from erp.gl_accounts where id = v_set.receivable_account_id),
      'account_name', (select name from erp.gl_accounts where id = v_set.receivable_account_id), 'debit', -v_final, 'credit', 0);
  end if;

  return jsonb_build_object(
    'tax_type', p_tax_type, 'year', p_year, 'quarter', p_quarter,
    'form', case p_tax_type when 'VAT' then '303' else '420' end,
    'period_start', v_start, 'period_end', v_end,
    'boxes', v_boxes,
    'output_tax', v_out, 'input_tax', v_in,
    'register_output', v_reg_out, 'register_input', v_reg_in,
    -- Cuadre auditor: el libro registro debe coincidir con la contabilidad
    'difference', (v_out - v_in) - (v_reg_out - v_reg_in),
    'result', v_result, 'carry_available', v_carry, 'carry_applied', v_applied,
    'final_result', v_final, 'outcome', v_outcome,
    'can_refund', p_quarter = 4 and v_final < 0,
    'lines', v_lines,
    'settled', v_done.id is not null, 'settlement_id', v_done.id);
end $$;

-- ---------------------------------------------------------------------
-- CONTABILIZAR la liquidación
-- ---------------------------------------------------------------------
create or replace function erp.post_tax_settlement(
  p_company uuid, p_tax_type text, p_year int, p_quarter int, p_refund boolean default false,
  p_accept_difference boolean default false)
returns table (settlement_id uuid, entry_no int, final_result numeric, outcome text)
language plpgsql as $$
declare
  c         jsonb;
  v_fy      erp.fiscal_years;
  v_entry   uuid;
  v_no      int;
  v_id      uuid;
begin
  if not erp.can_write(p_company) then
    raise exception 'No permission to post tax settlements in this company';
  end if;
  perform pg_advisory_xact_lock(hashtext('settlement/' || p_company || '/' || p_tax_type));

  if exists (select 1 from erp.tax_settlements s where s.company_id = p_company and s.tax_type = p_tax_type
             and s.status = 'posted' and (s.year, s.quarter) >= (p_year, p_quarter)) then
    raise exception 'Quarter %T % (or a later one) is already settled', p_quarter, p_year;
  end if;

  c := erp.tax_settlement_calc(p_company, p_tax_type, p_year, p_quarter, p_refund);
  -- Control auditor: lo que se declara (libro registro) debe coincidir con la contabilidad (472/477).
  -- Si no coincide, hay que aceptarlo expresamente y la diferencia queda guardada en la liquidación.
  if (c->>'difference')::numeric <> 0 and not p_accept_difference then
    raise exception 'The invoice register and the tax accounts differ by %: review manual entries on 472/477 before settling',
      c->>'difference';
  end if;

  perform set_config('erp.tax_settlement_engine', 'on', true);

  if jsonb_array_length(c->'lines') > 0 then
    select * into v_fy from erp.fiscal_years
    where company_id = p_company and (c->>'period_end')::date between starting_date and ending_date;
    if v_fy.id is null then
      raise exception 'No fiscal year for %', c->>'period_end';
    end if;
    insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no)
    values (p_company, v_fy.id, (c->>'period_end')::date,
            'Liquidación ' || case p_tax_type when 'VAT' then 'IVA' else 'IGIC' end || ' ' || p_quarter || 'T ' || p_year
              || ' (modelo ' || (c->>'form') || ')',
            (c->>'form') || '-' || p_year || '-' || p_quarter || 'T')
    returning id into v_entry;

    insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit)
    select v_entry, p_company, x.ord, g.id, (x.l->>'debit')::numeric, (x.l->>'credit')::numeric
    from jsonb_array_elements(c->'lines') with ordinality as x(l, ord)
    join erp.gl_accounts g on g.company_id = p_company and g.account_no = x.l->>'account_no';

    v_no := erp.post_entry(v_entry);
  end if;

  insert into erp.tax_settlements (company_id, tax_type, year, quarter, period_start, period_end, output_tax, input_tax,
                                   carry_applied, final_result, register_difference, outcome, entry_id)
  values (p_company, p_tax_type, p_year, p_quarter, (c->>'period_start')::date, (c->>'period_end')::date,
          (c->>'output_tax')::numeric, (c->>'input_tax')::numeric, (c->>'carry_applied')::numeric,
          (c->>'final_result')::numeric, (c->>'difference')::numeric, c->>'outcome', v_entry)
  returning id into v_id;

  perform set_config('erp.tax_settlement_engine', 'off', true);
  return query select v_id, v_no, (c->>'final_result')::numeric, c->>'outcome';
end $$;

-- ---------------------------------------------------------------------
-- DESHACER la última liquidación (p. ej. llegó una factura tarde del trimestre)
-- ---------------------------------------------------------------------
create or replace function erp.cancel_tax_settlement(p_settlement uuid)
returns void language plpgsql as $$
declare
  s erp.tax_settlements;
begin
  select * into s from erp.tax_settlements where id = p_settlement and status = 'posted';
  if not found then
    raise exception 'Settlement not found';
  end if;
  if not erp.can_write(s.company_id) then
    raise exception 'No permission to cancel tax settlements in this company';
  end if;
  if exists (select 1 from erp.tax_settlements x where x.company_id = s.company_id and x.tax_type = s.tax_type
             and x.status = 'posted' and (x.year, x.quarter) > (s.year, s.quarter)) then
    raise exception 'Only the last settlement can be cancelled';
  end if;
  perform set_config('erp.tax_settlement_engine', 'on', true);
  if s.entry_id is not null then
    perform erp.reverse_entry(s.entry_id);
  end if;
  update erp.tax_settlements set status = 'cancelled' where id = s.id;
  perform set_config('erp.tax_settlement_engine', 'off', true);
end $$;

-- ---------------------------------------------------------------------
-- BLOQUEO: un trimestre liquidado no admite nuevos apuntes en sus cuentas de impuesto
-- (si no, el modelo presentado y la contabilidad dejarían de coincidir)
-- ---------------------------------------------------------------------
create or replace function erp.tg_line_tax_period_lock()
returns trigger language plpgsql as $$
declare
  v_entry  erp.journal_entries;
  v_type   text;
  v_q      erp.tax_settlements;
begin
  if coalesce(current_setting('erp.tax_settlement_engine', true), '') = 'on'
     or coalesce(current_setting('erp.deleting_company', true), '') = 'on' then
    return new;
  end if;
  select * into v_entry from erp.journal_entries where id = new.entry_id;
  select c.tax_type into v_type
  from erp.tax_setup s join erp.tax_codes c on c.code = s.tax_code
  where s.company_id = v_entry.company_id and new.gl_account_id in (s.input_account_id, s.output_account_id)
  limit 1;
  if v_type is null then
    return new;
  end if;
  select * into v_q from erp.tax_settlements
  where company_id = v_entry.company_id and tax_type = v_type and status = 'posted'
    and v_entry.posting_date <= period_end
  order by period_end desc limit 1;
  if found then
    raise exception '% quarter %T % is already settled: post this with a later date (or cancel the settlement)',
      v_type, v_q.quarter, v_q.year;
  end if;
  return new;
end $$;

create trigger line_tax_period_lock before insert on erp.journal_lines
  for each row execute function erp.tg_line_tax_period_lock();

-- ---------------------------------------------------------------------
-- Vista para la web
-- ---------------------------------------------------------------------
create or replace view erp.v_tax_settlements with (security_invoker = true) as
select s.id, s.company_id, s.tax_type, s.year, s.quarter, s.period_start, s.period_end,
       case s.tax_type when 'VAT' then '303' else '420' end as form,
       s.output_tax, s.input_tax, s.carry_applied, s.final_result, s.register_difference, s.outcome, s.status, s.created_at,
       e.entry_no
from erp.tax_settlements s
left join erp.journal_entries e on e.id = s.entry_id;

alter table erp.tax_settlements enable row level security;
create policy read  on erp.tax_settlements for select to authenticated using (erp.can_read(company_id));
create policy write on erp.tax_settlements for all to authenticated
  using (erp.can_write(company_id)) with check (erp.can_write(company_id));

revoke all on erp.tax_settlements, erp.v_tax_settlements from anon, public;
grant select, insert, update on erp.tax_settlements to authenticated;
grant select on erp.v_tax_settlements to authenticated;

revoke execute on function erp.quarter_start(int, int), erp.quarter_end(int, int), erp.is_settlement_entry(uuid),
  erp.tax_settlement_calc(uuid, text, int, int, boolean), erp.post_tax_settlement(uuid, text, int, int, boolean, boolean),
  erp.cancel_tax_settlement(uuid) from anon, public;
grant execute on function erp.quarter_start(int, int), erp.quarter_end(int, int), erp.is_settlement_entry(uuid),
  erp.tax_settlement_calc(uuid, text, int, int, boolean), erp.post_tax_settlement(uuid, text, int, int, boolean, boolean),
  erp.cancel_tax_settlement(uuid) to authenticated;
