-- =====================================================================
-- 0017 · YEAR-END CLOSING · Cierre del ejercicio (bloque M)
-- ---------------------------------------------------------------------
-- Asistente de cierre en 4 pasos, como el de A3 / Sage / ContaPlus:
--   1. Comprobaciones   → borradores, ejercicio anterior, trimestres de IVA/IGIC, saldos anómalos
--   2. Regularización   → los grupos 6 y 7 se saldan contra la 129 Resultado del ejercicio  (closing_pl, 31/12)
--   3. Cierre           → todas las cuentas de balance (grupos 1 a 5) quedan a cero          (closing,    31/12)
--   4. Apertura         → mismos saldos, al revés, el 1/1 del ejercicio siguiente             (opening,    01/01)
-- y el ejercicio queda CERRADO: no admite más asientos.
--
-- Equivalencias:
--   BC  → "Close Income Statement" (regularización) + "Close Year" en Accounting Periods
--   SAP → FAGLGVTR "Balance Carryforward" (arrastre de saldos) + OB52 (cerrar periodos)
--
--   erp.year_closing_preview(empresa, año)            → borrador: comprobaciones, resultado y asientos
--   erp.close_fiscal_year(empresa, año, aceptar_avisos) → contabiliza los 3 asientos y cierra
--   erp.reopen_fiscal_year(empresa, año)              → anula los 3 asientos (contraasientos) y reabre
--
-- Los informes (balance y PyG) NO cuentan los asientos de regularización y cierre: se ven igual antes y
-- después de cerrar. La apertura SÍ cuenta: es el saldo inicial del año siguiente.
-- =====================================================================

create table erp.year_closings (
  id                   uuid primary key default gen_random_uuid(),
  company_id           uuid not null references erp.companies(id) on delete cascade,
  fiscal_year_id       uuid not null references erp.fiscal_years(id) on delete cascade,
  year                 smallint not null,
  result               numeric(15,2) not null,     -- > 0 beneficio · < 0 pérdida
  closing_pl_entry_id  uuid references erp.journal_entries(id),   -- regularización
  closing_entry_id     uuid references erp.journal_entries(id),   -- cierre
  opening_entry_id     uuid references erp.journal_entries(id),   -- apertura del año siguiente
  warnings             jsonb not null default '[]',               -- avisos aceptados al cerrar
  status               text not null default 'posted' check (status in ('posted', 'cancelled')),
  created_by           uuid default auth.uid(),
  created_at           timestamptz not null default now()
);
create unique index year_closings_unique_posted on erp.year_closings (fiscal_year_id) where status = 'posted';

-- Solo el motor de cierre crea o cancela cierres, y solo él abre o cierra un ejercicio
create or replace function erp.tg_year_closing_protect()
returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('erp.deleting_company', true), '') = 'on'
     or coalesce(current_setting('erp.year_closing_engine', true), '') = 'on' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  raise exception 'Year-end closings are created only with close_fiscal_year()';
end $$;

create trigger year_closing_protect before insert or update or delete on erp.year_closings
  for each row execute function erp.tg_year_closing_protect();

create or replace function erp.tg_fiscal_year_status()
returns trigger language plpgsql as $$
begin
  if new.status <> old.status and coalesce(current_setting('erp.year_closing_engine', true), '') <> 'on' then
    raise exception 'Use the year-end closing to close or reopen fiscal year %', old.year;
  end if;
  return new;
end $$;

create trigger fiscal_year_status before update of status on erp.fiscal_years
  for each row execute function erp.tg_fiscal_year_status();

-- ¿Es un asiento del cierre (o la anulación de uno)?
create or replace function erp.is_year_closing_entry(p_entry uuid)
returns boolean language sql stable as $$
  select exists (select 1 from erp.year_closings c
                 join erp.journal_entries e on e.id = p_entry
                 where coalesce(e.reversal_of, e.id) in (c.closing_pl_entry_id, c.closing_entry_id, c.opening_entry_id));
$$;

-- Saldo de cada subcuenta en un ejercicio (> 0 deudor · < 0 acreedor)
create or replace function erp.year_account_balances(p_fiscal_year uuid)
returns table (account_id uuid, account_no text, account_name text, balance numeric)
language sql stable as $$
  select g.id, g.account_no, g.name, sum(l.debit - l.credit)
  from erp.journal_lines l
  join erp.journal_entries e on e.id = l.entry_id and e.status = 'posted'
  join erp.gl_accounts g     on g.id = l.gl_account_id
  where e.fiscal_year_id = p_fiscal_year
  group by g.id, g.account_no, g.name
  having sum(l.debit - l.credit) <> 0
  order by g.account_no;
$$;

-- Subcuenta de la 129 (la primera que cuelga de la 129, o la que se creará: 129 + ceros)
create or replace function erp.result_account_no(p_company uuid)
returns text language sql stable as $$
  select coalesce(
    (select account_no from erp.gl_accounts
     where company_id = p_company and account_type = 'posting' and template_account = '129'
     order by account_no limit 1),
    (select rpad('129', posting_account_digits, '0') from erp.companies where id = p_company));
$$;

-- ---------------------------------------------------------------------
-- BORRADOR DEL CIERRE (no guarda nada)
-- ---------------------------------------------------------------------
create or replace function erp.year_closing_preview(p_company uuid, p_year int)
returns jsonb language plpgsql stable as $$
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
end $$;

-- Crea y contabiliza un asiento a partir de líneas jsonb [{account_no, debit, credit}]
create or replace function erp.post_closing_entry(
  p_company uuid, p_fiscal_year uuid, p_date date, p_type text, p_description text, p_document text, p_lines jsonb)
returns uuid language plpgsql as $$
declare
  v_entry uuid;
begin
  if coalesce(current_setting('erp.year_closing_engine', true), '') <> 'on' then
    raise exception 'Closing entries are created only with close_fiscal_year()';
  end if;
  if jsonb_array_length(p_lines) = 0 then
    return null;
  end if;
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no, entry_type)
  values (p_company, p_fiscal_year, p_date, p_description, p_document, p_type)
  returning id into v_entry;

  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit)
  select v_entry, p_company, x.ord, g.id, (x.l->>'debit')::numeric, (x.l->>'credit')::numeric
  from jsonb_array_elements(p_lines) with ordinality as x(l, ord)
  join erp.gl_accounts g on g.company_id = p_company and g.account_no = x.l->>'account_no';
  -- Los saldos de 472/477 que pasan de año no son operaciones del libro registro
  update erp.journal_lines set tax_code = null where entry_id = v_entry;

  perform erp.post_entry(v_entry);
  return v_entry;
end $$;

-- ---------------------------------------------------------------------
-- CERRAR EL EJERCICIO
-- ---------------------------------------------------------------------
create or replace function erp.close_fiscal_year(p_company uuid, p_year int, p_accept_warnings boolean default false)
returns table (closing_id uuid, result numeric, closing_pl_no int, closing_no int, opening_no int)
language plpgsql as $$
declare
  c        jsonb;
  v_fy     erp.fiscal_years;
  v_next   uuid;
  v_pl     uuid;
  v_close  uuid;
  v_open   uuid;
  v_id     uuid;
  v_res_no text;
begin
  if not erp.is_admin(p_company) then
    raise exception 'Only the company admin can close the fiscal year';
  end if;
  perform pg_advisory_xact_lock(hashtext('closing/' || p_company));

  c := erp.year_closing_preview(p_company, p_year);
  if (c->>'status') = 'closed' then
    raise exception 'Fiscal year % is already closed', p_year;
  end if;
  if not (c->>'can_close')::boolean then
    raise exception 'Fiscal year % cannot be closed: %', p_year,
      (select string_agg((x->>'code') || ' (' || (x->>'detail') || ')', ', ')
       from jsonb_array_elements(c->'checks') x where x->>'severity' = 'error');
  end if;
  if (c->>'has_warnings')::boolean and not p_accept_warnings then
    raise exception 'Review and accept the warnings before closing: %',
      (select string_agg((x->>'code') || ' (' || (x->>'detail') || ')', ', ')
       from jsonb_array_elements(c->'checks') x where x->>'severity' = 'warning');
  end if;

  perform set_config('erp.year_closing_engine', 'on', true);
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;

  -- Subcuenta 129 y ejercicio siguiente, si no existen
  v_res_no := c->>'result_account_no';
  if not exists (select 1 from erp.gl_accounts where company_id = p_company and account_no = v_res_no) then
    perform erp.create_posting_account(p_company, v_res_no, 'Resultado del ejercicio', 'Profit (loss) for the year');
  end if;
  select id into v_next from erp.fiscal_years where company_id = p_company and year = p_year + 1;
  if v_next is null then
    v_next := erp.create_fiscal_year(p_company, p_year + 1);
  end if;

  -- 2) Regularización · 3) Cierre (31/12) · 4) Apertura (1/1), con las líneas del cierre al revés
  v_pl := erp.post_closing_entry(p_company, v_fy.id, v_fy.ending_date, 'closing_pl',
            'Regularización del ejercicio ' || p_year, 'REG-' || p_year, c->'closing_pl_lines');
  v_close := erp.post_closing_entry(p_company, v_fy.id, v_fy.ending_date, 'closing',
            'Asiento de cierre del ejercicio ' || p_year, 'CIE-' || p_year, c->'closing_lines');
  v_open := erp.post_closing_entry(p_company, v_next, v_fy.ending_date + 1, 'opening',
            'Asiento de apertura del ejercicio ' || (p_year + 1), 'APE-' || (p_year + 1),
            (select coalesce(jsonb_agg(jsonb_build_object('account_no', l->>'account_no',
                               'debit', l->'credit', 'credit', l->'debit')), '[]')
             from jsonb_array_elements(c->'closing_lines') l));

  insert into erp.year_closings (company_id, fiscal_year_id, year, result, closing_pl_entry_id, closing_entry_id,
                                 opening_entry_id, warnings)
  values (p_company, v_fy.id, p_year, (c->>'result')::numeric, v_pl, v_close, v_open,
          (select coalesce(jsonb_agg(x), '[]') from jsonb_array_elements(c->'checks') x where x->>'severity' = 'warning'))
  returning id into v_id;

  update erp.fiscal_years set status = 'closed' where id = v_fy.id;
  perform set_config('erp.year_closing_engine', 'off', true);

  return query select v_id, (c->>'result')::numeric,
    (select entry_no from erp.journal_entries where id = v_pl),
    (select entry_no from erp.journal_entries where id = v_close),
    (select entry_no from erp.journal_entries where id = v_open);
end $$;

-- ---------------------------------------------------------------------
-- REABRIR EL EJERCICIO (para registrar un ajuste tardío). Los asientos del cierre no se borran:
-- se anulan con contraasientos, como hace SAP, y queda la traza para el auditor.
-- ---------------------------------------------------------------------
create or replace function erp.reopen_fiscal_year(p_company uuid, p_year int)
returns void language plpgsql as $$
declare
  v_c    erp.year_closings;
  v_fy   erp.fiscal_years;
begin
  if not erp.is_admin(p_company) then
    raise exception 'Only the company admin can reopen the fiscal year';
  end if;
  perform pg_advisory_xact_lock(hashtext('closing/' || p_company));
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;
  select * into v_c from erp.year_closings where fiscal_year_id = v_fy.id and status = 'posted';
  if v_c.id is null then
    raise exception 'Fiscal year % is not closed', p_year;
  end if;
  if exists (select 1 from erp.fiscal_years where company_id = p_company and year = p_year + 1 and status = 'closed') then
    raise exception 'Reopen fiscal year % first', p_year + 1;
  end if;

  perform set_config('erp.year_closing_engine', 'on', true);
  update erp.fiscal_years set status = 'open' where id = v_fy.id;
  if v_c.opening_entry_id is not null then perform erp.reverse_entry(v_c.opening_entry_id, null, 'Reapertura del ejercicio ' || p_year); end if;
  if v_c.closing_entry_id is not null then perform erp.reverse_entry(v_c.closing_entry_id, null, 'Reapertura del ejercicio ' || p_year); end if;
  if v_c.closing_pl_entry_id is not null then perform erp.reverse_entry(v_c.closing_pl_entry_id, null, 'Reapertura del ejercicio ' || p_year); end if;
  update erp.year_closings set status = 'cancelled' where id = v_c.id;
  perform set_config('erp.year_closing_engine', 'off', true);
end $$;

-- ---------------------------------------------------------------------
-- AJUSTES EN FUNCIONES ANTERIORES
-- ---------------------------------------------------------------------

-- Anular: los asientos del cierre solo se anulan reabriendo el ejercicio
create or replace function erp.reverse_entry(p_entry uuid, p_posting_date date default null, p_reason text default null)
returns integer language plpgsql as $$
declare
  v_e     erp.journal_entries;
  v_date  date;
  v_fy    uuid;
  v_new   uuid;
  v_no    int;
begin
  select * into v_e from erp.journal_entries where id = p_entry;
  if not found then raise exception 'Entry not found (or no permission)'; end if;
  if not erp.can_write(v_e.company_id) then
    raise exception 'No permission to reverse entries in this company';
  end if;
  if v_e.status <> 'posted' then
    raise exception 'Only posted entries can be reversed; a draft can simply be deleted';
  end if;
  if v_e.reversed_by is not null then raise exception 'Entry % is already reversed', v_e.entry_no; end if;
  if v_e.reversal_of is not null then raise exception 'A reversal entry cannot be reversed'; end if;
  if coalesce(current_setting('erp.tax_settlement_engine', true), '') <> 'on'
     and exists (select 1 from erp.tax_settlements s where s.entry_id = p_entry) then
    raise exception 'This entry belongs to a tax settlement: use "Undo settlement" instead';
  end if;
  if coalesce(current_setting('erp.year_closing_engine', true), '') <> 'on' and erp.is_year_closing_entry(p_entry) then
    raise exception 'This entry belongs to a year-end closing: reopen the fiscal year instead';
  end if;

  v_date := coalesce(p_posting_date, v_e.posting_date);
  if v_date < v_e.posting_date then
    raise exception 'The reversal date cannot be earlier than the original entry (%)', v_e.posting_date;
  end if;
  select id into v_fy from erp.fiscal_years
  where company_id = v_e.company_id and v_date between starting_date and ending_date;
  if v_fy is null then raise exception 'No fiscal year for date %', v_date; end if;

  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no, entry_type,
                                   reversal_of, reversal_reason)
  values (v_e.company_id, v_fy, v_date,
          'Anulación del asiento ' || v_e.entry_no || ': ' || v_e.description
            || coalesce(' · ' || nullif(btrim(p_reason), ''), ''),
          v_e.document_no, v_e.entry_type, v_e.id, nullif(btrim(p_reason), ''))
  returning id into v_new;

  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description,
                                 partner_id, tax_code, tax_base)
  select v_new, company_id, line_no, gl_account_id, credit, debit, description,
         partner_id, tax_code, -tax_base
  from erp.journal_lines where entry_id = v_e.id;
  if erp.is_year_closing_entry(v_e.id) then
    update erp.journal_lines set tax_code = null where entry_id = v_new;
  end if;

  v_no := erp.post_entry(v_new);
  update erp.journal_entries set reversed_by = v_new where id = v_e.id;
  return v_no;
end $$;

-- Liquidación de IVA/IGIC: los asientos del cierre no son movimiento del trimestre
create or replace function erp.is_settlement_entry(p_entry uuid)
returns boolean language sql stable as $$
  select exists (select 1 from erp.tax_settlements s
                 join erp.journal_entries e on e.id = p_entry
                 where s.entry_id = e.id or s.entry_id = e.reversal_of)
      or erp.is_year_closing_entry(p_entry);
$$;

-- Bloqueo de trimestres liquidados: no se aplica a los asientos del cierre
create or replace function erp.tg_line_tax_period_lock()
returns trigger language plpgsql as $$
declare
  v_entry  erp.journal_entries;
  v_type   text;
  v_q      erp.tax_settlements;
begin
  if coalesce(current_setting('erp.tax_settlement_engine', true), '') = 'on'
     or coalesce(current_setting('erp.year_closing_engine', true), '') = 'on'
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

-- Balance y PyG: sin los asientos de regularización y cierre (se ven igual antes y después de cerrar)
create or replace function erp.fs_classified_accounts(p_company uuid, p_year int, p_statement text, p_to_date date default null)
returns table (account_no text, account_name text, account_name_en text, balance numeric, line_code text, amount numeric)
language sql stable as $$
  with acc as (
    select g.account_no, g.name, g.name_en, sum(l.debit - l.credit) as bal
    from erp.journal_lines l
    join erp.journal_entries e on e.id = l.entry_id and e.status = 'posted'
                              and e.entry_type not in ('closing_pl', 'closing')
    join erp.fiscal_years fy   on fy.id = e.fiscal_year_id and fy.year = p_year
    join erp.gl_accounts g     on g.id = l.gl_account_id
    where e.company_id = p_company
      and (p_to_date is null or e.posting_date <= p_to_date)
      and (p_statement = 'balance' or left(g.account_no, 1) in ('6', '7'))
    group by g.account_no, g.name, g.name_en
    having sum(l.debit - l.credit) <> 0
  )
  select a.account_no, a.name, a.name_en, a.bal,
         m.line,
         a.bal * case fl.side when 'debit' then 1 else -1 end
  from acc a
  cross join lateral (
    select case when a.bal >= 0 then fm.debit_line else fm.credit_line end as line
    from erp.fs_mapping fm
    where fm.statement = p_statement and a.account_no like fm.prefix || '%'
    order by length(fm.prefix) desc limit 1) m
  join erp.fs_lines fl on fl.statement = p_statement and fl.code = m.line;
$$;

-- Libro diario: origen 'closing' para los asientos del cierre (no se anulan desde el diario)
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

-- Historial de cierres para la web
create or replace view erp.v_year_closings with (security_invoker = true) as
select c.id, c.company_id, c.year, c.result, c.status, c.warnings, c.created_at,
       pl.entry_no as closing_pl_no, cl.entry_no as closing_no, op.entry_no as opening_no
from erp.year_closings c
left join erp.journal_entries pl on pl.id = c.closing_pl_entry_id
left join erp.journal_entries cl on cl.id = c.closing_entry_id
left join erp.journal_entries op on op.id = c.opening_entry_id;

-- ---------------------------------------------------------------------
-- Seguridad
-- ---------------------------------------------------------------------
alter table erp.year_closings enable row level security;
create policy read  on erp.year_closings for select to authenticated using (erp.can_read(company_id));
create policy write on erp.year_closings for all to authenticated
  using (erp.is_admin(company_id)) with check (erp.is_admin(company_id));

revoke all on erp.year_closings, erp.v_year_closings from anon, public;
grant select, insert, update on erp.year_closings to authenticated;
grant select on erp.v_year_closings, erp.v_general_journal to authenticated;

revoke execute on function erp.is_year_closing_entry(uuid), erp.year_account_balances(uuid), erp.result_account_no(uuid),
  erp.year_closing_preview(uuid, int), erp.post_closing_entry(uuid, uuid, date, text, text, text, jsonb),
  erp.close_fiscal_year(uuid, int, boolean), erp.reopen_fiscal_year(uuid, int) from anon, public;
grant execute on function erp.is_year_closing_entry(uuid), erp.year_account_balances(uuid), erp.result_account_no(uuid),
  erp.year_closing_preview(uuid, int), erp.post_closing_entry(uuid, uuid, date, text, text, text, jsonb),
  erp.close_fiscal_year(uuid, int, boolean), erp.reopen_fiscal_year(uuid, int) to authenticated;
