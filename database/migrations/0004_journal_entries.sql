-- =====================================================================
-- 0004 · JOURNAL ENTRIES & LINES · Asientos y apuntes
-- ---------------------------------------------------------------------
-- Equivalencias / Equivalents:
--   journal_entries (header)  ≈ SAP BKPF  ≈ BC "Document No." grouping G/L Entries   · asiento (cabecera)
--   journal_lines   (lines)   ≈ SAP BSEG  ≈ BC "G/L Entry"                            · apunte (línea)
--
-- Vocabulario: debit = Debe · credit = Haber · posting date = fecha contable ·
--              post = contabilizar · reverse = anular (con contraasiento) · balanced = cuadrado
--
-- Ciclo de vida (ver docs/decisiones/0002-asientos.md):
--   draft ──post_entry()──► posted ──reverse_entry()──► genera un contraasiento (reversal entry)
--
-- Reglas que garantiza la base de datos (no la web):
--   1. Un asiento posted es INMUTABLE: ni se edita ni se borra.
--   2. Solo se contabiliza si Debe = Haber, con ≥ 2 apuntes y en periodo abierto.
--   3. Solo se apunta en subcuentas (account_type 'posting') de la misma empresa y no bloqueadas.
--   4. Numeración correlativa por ejercicio, asignada al contabilizar (sin huecos).
-- =====================================================================

create table erp.journal_entries (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null references erp.companies(id) on delete cascade,
  fiscal_year_id  uuid not null references erp.fiscal_years(id),
  entry_no        integer,                 -- se asigna al contabilizar
  posting_date    date not null,
  description     text not null,           -- concepto
  document_no     text,                    -- nº de factura, recibo…
  entry_type      text not null default 'normal'
                  check (entry_type in ('opening', 'normal', 'closing_pl', 'closing')),
                  -- apertura, normal, regularización (cierre de PyG a la 129), cierre
  status          text not null default 'draft'
                  check (status in ('draft', 'posted')),        -- borrador, contabilizado
  reversal_of     uuid references erp.journal_entries(id),     -- si es un contraasiento
  reversed_by     uuid references erp.journal_entries(id),     -- si fue anulado
  created_by      uuid default auth.uid(),
  created_at      timestamptz not null default now(),
  posted_at       timestamptz,
  unique (fiscal_year_id, entry_no)
);
create index journal_entries_company_date on erp.journal_entries (company_id, posting_date);

create table erp.journal_lines (
  id             uuid primary key default gen_random_uuid(),
  entry_id       uuid not null references erp.journal_entries(id) on delete cascade,
  company_id     uuid not null references erp.companies(id) on delete cascade,
  line_no        smallint not null,
  gl_account_id  uuid not null references erp.gl_accounts(id),
  debit          numeric(15,2) not null default 0 check (debit  >= 0),
  credit         numeric(15,2) not null default 0 check (credit >= 0),
  description    text,
  partner_id     uuid references erp.business_partners(id),
  -- Solo en apuntes de cuotas de impuesto (472 / 477): alimentan el libro registro
  tax_code       text references erp.tax_codes(code),
  tax_base       numeric(15,2),            -- base imponible
  -- Cada apunte va al Debe O al Haber, nunca a los dos ni a ninguno
  check ((debit > 0 and credit = 0) or (credit > 0 and debit = 0)),
  unique (entry_id, line_no)
);
create index journal_lines_account on erp.journal_lines (gl_account_id);
create index journal_lines_entry on erp.journal_lines (entry_id);

-- ---------------------------------------------------------------------
-- Validación de la cabecera: la fecha debe caer en el ejercicio indicado
-- ---------------------------------------------------------------------
create or replace function erp.tg_entry_validate()
returns trigger language plpgsql as $$
declare
  v_fy erp.fiscal_years;
begin
  if tg_op = 'UPDATE' and old.status = 'posted' then
    -- Único cambio permitido sobre un asiento contabilizado: marcarlo como anulado.
    if (to_jsonb(new) - 'reversed_by') <> (to_jsonb(old) - 'reversed_by')
       or old.reversed_by is not null then
      raise exception 'Entry % is posted and cannot be changed. Reverse it instead.', old.entry_no;
    end if;
    return new;
  end if;

  select * into v_fy from erp.fiscal_years where id = new.fiscal_year_id;
  if v_fy.company_id <> new.company_id then
    raise exception 'The fiscal year does not belong to the company of the entry';
  end if;
  if new.posting_date not between v_fy.starting_date and v_fy.ending_date then
    raise exception 'Posting date % is outside fiscal year %', new.posting_date, v_fy.year;
  end if;
  return new;
end $$;

create trigger entry_validate
  before insert or update on erp.journal_entries
  for each row execute function erp.tg_entry_validate();

create or replace function erp.tg_entry_prevent_delete()
returns trigger language plpgsql as $$
begin
  if old.status = 'posted' and coalesce(current_setting('erp.deleting_company', true), '') <> 'on' then
    raise exception 'Entry % is posted and cannot be deleted. Reverse it instead.', old.entry_no;
  end if;
  return old;
end $$;

create trigger entry_prevent_delete
  before delete on erp.journal_entries
  for each row execute function erp.tg_entry_prevent_delete();

-- ---------------------------------------------------------------------
-- Validación de apuntes
-- ---------------------------------------------------------------------
create or replace function erp.tg_line_validate()
returns trigger language plpgsql as $$
declare
  v_entry    erp.journal_entries;
  v_account  erp.gl_accounts;
begin
  if coalesce(current_setting('erp.deleting_company', true), '') = 'on' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  -- 1) El asiento debe estar en borrador (vale para INSERT, UPDATE y DELETE)
  select * into v_entry from erp.journal_entries
  where id = case when tg_op = 'DELETE' then old.entry_id else new.entry_id end;

  if v_entry.status = 'posted' then
    raise exception 'Entry % is posted: its lines cannot be changed', v_entry.entry_no;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  -- 2) La empresa del apunte es siempre la del asiento
  new.company_id := v_entry.company_id;

  -- 3) La cuenta: de la misma empresa, subcuenta y no bloqueada
  select * into v_account from erp.gl_accounts where id = new.gl_account_id;
  if v_account.company_id <> new.company_id then
    raise exception 'Account % does not belong to this company', v_account.account_no;
  end if;
  if v_account.account_type <> 'posting' then
    raise exception 'Account % (%) is a heading account: use a posting account', v_account.account_no, v_account.name;
  end if;
  if v_account.blocked then
    raise exception 'Account % is blocked', v_account.account_no;
  end if;

  -- 4) Número de línea automático si no se indica
  if new.line_no is null then
    select coalesce(max(line_no), 0) + 1 into new.line_no from erp.journal_lines where entry_id = new.entry_id;
  end if;
  return new;
end $$;

create trigger line_validate
  before insert or update or delete on erp.journal_lines
  for each row execute function erp.tg_line_validate();

-- ---------------------------------------------------------------------
-- POST ENTRY · Contabilizar: valida cuadre y periodo, asigna número y bloquea el asiento
-- ---------------------------------------------------------------------
create or replace function erp.post_entry(p_entry uuid)
returns integer language plpgsql as $$
declare
  v_e       erp.journal_entries;
  v_debit   numeric(15,2);
  v_credit  numeric(15,2);
  v_lines   int;
  v_period  erp.accounting_periods;
  v_fy      erp.fiscal_years;
  v_no      int;
begin
  select * into v_e from erp.journal_entries where id = p_entry for update;
  if not found then
    raise exception 'Entry not found (or no permission)';
  end if;
  if v_e.status <> 'draft' then
    raise exception 'Entry is already posted with number %', v_e.entry_no;
  end if;

  select coalesce(sum(debit), 0), coalesce(sum(credit), 0), count(*)
  into v_debit, v_credit, v_lines
  from erp.journal_lines where entry_id = p_entry;

  if v_lines < 2 then
    raise exception 'An entry needs at least 2 lines (it has %)', v_lines;
  end if;
  if v_debit <> v_credit then
    raise exception 'Unbalanced entry: debit % ≠ credit % (difference %)', v_debit, v_credit, v_debit - v_credit;
  end if;

  -- Bloqueo por ejercicio: si dos usuarios contabilizan a la vez, uno espera → sin huecos ni duplicados
  perform pg_advisory_xact_lock(hashtext(v_e.fiscal_year_id::text));
  select * into v_fy from erp.fiscal_years where id = v_e.fiscal_year_id;
  if v_fy.status <> 'open' then
    raise exception 'Fiscal year % is closed', v_fy.year;
  end if;

  select * into v_period from erp.accounting_periods
  where fiscal_year_id = v_e.fiscal_year_id and v_e.posting_date between starting_date and ending_date;
  if v_period.status <> 'open' then
    raise exception 'Period % of % is closed', v_period.period_no, v_fy.year;
  end if;

  select coalesce(max(entry_no), 0) + 1 into v_no
  from erp.journal_entries where fiscal_year_id = v_e.fiscal_year_id;

  update erp.journal_entries
  set status = 'posted', entry_no = v_no, posted_at = now()
  where id = p_entry;

  return v_no;
end $$;

-- ---------------------------------------------------------------------
-- REVERSE ENTRY · Anular: crea y contabiliza un contraasiento (Debe ↔ Haber). El original se conserva.
-- ---------------------------------------------------------------------
create or replace function erp.reverse_entry(p_entry uuid, p_posting_date date default null)
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
  if v_e.status <> 'posted' then
    raise exception 'Only posted entries can be reversed; a draft can simply be deleted';
  end if;
  if v_e.reversed_by is not null then raise exception 'Entry % is already reversed', v_e.entry_no; end if;
  if v_e.reversal_of is not null then raise exception 'A reversal entry cannot be reversed'; end if;

  v_date := coalesce(p_posting_date, v_e.posting_date);
  select id into v_fy from erp.fiscal_years
  where company_id = v_e.company_id and v_date between starting_date and ending_date;
  if v_fy is null then raise exception 'No fiscal year for date %', v_date; end if;

  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no, entry_type, reversal_of)
  values (v_e.company_id, v_fy, v_date, 'REVERSAL of entry ' || v_e.entry_no || ': ' || v_e.description,
          v_e.document_no, v_e.entry_type, v_e.id)
  returning id into v_new;

  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description,
                                 partner_id, tax_code, tax_base)
  select v_new, company_id, line_no, gl_account_id, credit, debit, description,
         partner_id, tax_code, -tax_base
  from erp.journal_lines where entry_id = v_e.id;

  v_no := erp.post_entry(v_new);
  update erp.journal_entries set reversed_by = v_new where id = v_e.id;
  return v_no;
end $$;

-- ---------------------------------------------------------------------
-- DELETE COMPANY · Eliminar empresa completa (solo su admin). Es la única vía para borrar
-- asientos contabilizados: pensado para empresas de práctica que ya no se usan.
-- ---------------------------------------------------------------------
create or replace function erp.delete_company(p_company uuid)
returns void language plpgsql security definer set search_path = erp, public as $$
begin
  if not exists (select 1 from erp.company_users
                 where company_id = p_company and user_id = auth.uid() and role = 'admin') then
    raise exception 'Only the company admin can delete it';
  end if;
  perform set_config('erp.deleting_company', 'on', true);   -- solo dura esta transacción
  delete from erp.companies where id = p_company;
  perform set_config('erp.deleting_company', 'off', true);
end $$;
