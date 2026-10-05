-- =====================================================================
-- 0011 · INVOICES · Registro de facturas recibidas y emitidas (modelo gestoría)
-- ---------------------------------------------------------------------
-- Como el registro de facturas de A3ECO / Sage / ContaPlus o las transacciones FB60 / FB70 de SAP:
-- la factura se registra desde contabilidad (sin artículos ni stock) y genera SU asiento contabilizado.
--
--   erp.invoices            → cabecera: tercero, nº de factura, fechas, tipo (factura / rectificativa)
--   erp.invoice_lines       → líneas: cuenta de base (grupo 2/6 compras · grupo 7 ventas), importe, tipo de impuesto
--   erp.invoice_tax_lines   → resumen por tipo de impuesto: base y cuota → LIBRO REGISTRO DE FACTURAS
--
--   erp.preview_invoice(json) → asiento que se generaría (sin guardar nada)  ≈ "Vista previa" de BC
--   erp.post_invoice(json)    → registra factura + asiento contabilizado, todo o nada
--
-- REGLA DEL LADO (la misma para todas las facturas):
--   Compras: la base va al DEBE · Ventas: la base va al HABER
--   Las cuentas que REDUCEN (606/608/609 en compras · 706/708/709 en ventas) van al lado contrario,
--   y en una RECTIFICATIVA todas las líneas reducen.
--   La cuota (472 compras / 477 ventas) va al mismo lado que su base; el tercero, al lado contrario por el total.
-- =====================================================================

create table erp.invoices (
  id                    uuid primary key default gen_random_uuid(),
  company_id            uuid not null references erp.companies(id) on delete cascade,
  fiscal_year_id        uuid not null references erp.fiscal_years(id),
  invoice_type          text not null check (invoice_type in ('purchase', 'sale')),       -- recibida / emitida
  document_kind         text not null check (document_kind in ('invoice', 'credit_memo')), -- factura / rectificativa
  invoice_no            text not null,     -- ventas: F-2026-0001 · compras: nº de registro C-2026-0001
  external_document_no  text,              -- compras: nº de factura del proveedor (BC "External Document No.")
  partner_id            uuid not null references erp.business_partners(id),
  invoice_date          date not null,     -- fecha de expedición
  posting_date          date not null,     -- fecha de registro / contabilización
  description           text not null,
  corrected_invoice_id  uuid references erp.invoices(id),   -- rectificativa: factura que corrige (si está en el sistema)
  corrected_reference   text,                               -- … o su número, si no está
  total_base            numeric(15,2) not null,
  total_tax             numeric(15,2) not null,
  total_amount          numeric(15,2) not null,
  entry_id              uuid not null references erp.journal_entries(id),
  created_by            uuid default auth.uid(),
  created_at            timestamptz not null default now(),
  unique (company_id, invoice_type, invoice_no),
  check (posting_date >= invoice_date)
);
-- Control de factura duplicada: un proveedor no emite dos veces el mismo número
create unique index invoices_unique_external
  on erp.invoices (company_id, partner_id, invoice_type, document_kind, upper(external_document_no))
  where external_document_no is not null;
create index invoices_company_date on erp.invoices (company_id, posting_date);

create table erp.invoice_lines (
  id             uuid primary key default gen_random_uuid(),
  invoice_id     uuid not null references erp.invoices(id) on delete cascade,
  company_id     uuid not null references erp.companies(id) on delete cascade,
  line_no        smallint not null,
  gl_account_id  uuid not null references erp.gl_accounts(id),
  description    text,
  amount         numeric(15,2) not null check (amount > 0),   -- importe tal como figura en la factura
  tax_code       text not null references erp.tax_codes(code),
  sign           smallint not null check (sign in (-1, 1)),    -- +1 aumenta la factura · −1 la reduce
  unique (invoice_id, line_no)
);

create table erp.invoice_tax_lines (
  invoice_id   uuid not null references erp.invoices(id) on delete cascade,
  company_id   uuid not null references erp.companies(id) on delete cascade,
  tax_code     text not null references erp.tax_codes(code),
  tax_base     numeric(15,2) not null,   -- con signo: negativo en rectificativas
  tax_amount   numeric(15,2) not null,
  primary key (invoice_id, tax_code)
);

-- ---------------------------------------------------------------------
-- Las facturas solo se crean con post_invoice() y no se modifican ni borran:
-- se corrigen con una rectificativa (igual que el asiento contabilizado se corrige con otro asiento)
-- ---------------------------------------------------------------------
create or replace function erp.tg_invoice_protect()
returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('erp.deleting_company', true), '') = 'on' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  if tg_op = 'INSERT' and coalesce(current_setting('erp.invoice_engine', true), '') = 'on' then
    return new;
  end if;
  raise exception 'Invoices are created only with post_invoice() and cannot be changed or deleted: issue a credit memo';
end $$;

create trigger invoice_protect before insert or update or delete on erp.invoices
  for each row execute function erp.tg_invoice_protect();
create trigger invoice_line_protect before insert or update or delete on erp.invoice_lines
  for each row execute function erp.tg_invoice_protect();
create trigger invoice_tax_line_protect before insert or update or delete on erp.invoice_tax_lines
  for each row execute function erp.tg_invoice_protect();

-- ---------------------------------------------------------------------
-- MOTOR: calcula el asiento de una factura a partir de un JSON
-- {company_id, invoice_type, document_kind, partner_id, external_document_no, invoice_date,
--  posting_date, description, corrected_invoice_id, corrected_reference,
--  lines: [{account_no, amount, tax_code, description}]}
-- Devuelve las líneas del asiento (cuenta, debe, haber, tipo, base). No guarda nada.
-- ---------------------------------------------------------------------
create or replace function erp.invoice_entry_lines(p jsonb)
returns table (line_no int, gl_account_id uuid, account_no text, account_name text,
               debit numeric, credit numeric, tax_code text, tax_base numeric, line_role text,
               src_line int, amount numeric, sign int, description text)
language plpgsql stable as $$
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
    if v_type = 'sale' and left(a.account_no, 1) <> '7' then
      raise exception 'Line %: account % is not valid in an issued invoice (use group 7)', r.n, a.account_no;
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

    -- Regla del lado: reducen las cuentas 606/608/609 · 706/708/709 y todas las líneas de una rectificativa
    v_sign := case when v_kind = 'credit_memo'
                     or a.template_account in ('606', '608', '609', '706', '708', '709') then -1 else 1 end;

    v_work := v_work || jsonb_build_object(
      'n', r.n, 'gl_account_id', a.id, 'account_no', a.account_no, 'account_name', a.name,
      'amount', round(r.amount_txt::numeric, 2), 'tax_code', r.code, 'sign', v_sign, 'rate', tc.rate_pct,
      'description', r.descr,
      'tax_account', case v_type when 'purchase' then s.input_account_id else s.output_account_id end);
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

  -- 2) Cuotas: una por tipo, sobre la base neta de la factura, redondeada a céntimos
  for t in
    select w.tax_code as code, max(w.rate) as rate, sum(w.sign * w.amount) as base,
           (array_agg(w.tax_account))[1] as acc
    from jsonb_to_recordset(v_work) as w(tax_code text, rate numeric, sign int, amount numeric, tax_account uuid)
    group by w.tax_code order by w.tax_code
  loop
    v_signed := round(t.base * t.rate / 100, 2);
    v_total := v_total + v_signed;
    src_line := null; amount := null; sign := null; description := null;
    tax_code := t.code; tax_base := t.base;
    if v_signed <> 0 then
      v_n := v_n + 1;
      line_no := v_n; gl_account_id := t.acc;
      select g.account_no, g.name into account_no, account_name from erp.gl_accounts g where g.id = t.acc;
      debit  := case when (v_type = 'purchase') = (v_signed > 0) then abs(v_signed) else 0 end;
      credit := case when (v_type = 'purchase') = (v_signed > 0) then 0 else abs(v_signed) end;
      line_role := 'tax';
    else
      -- tipo 0 % o exento: no hay apunte, pero sí base para el libro registro
      line_no := null; gl_account_id := null; account_no := null; account_name := null;
      debit := 0; credit := 0; line_role := 'tax_exempt';
    end if;
    return next;
  end loop;

  -- 3) Tercero: lado contrario, por el total
  if v_total = 0 then
    raise exception 'The invoice total is zero';
  end if;
  if v_kind = 'invoice' and v_total < 0 then
    raise exception 'The invoice total is negative: register it as a credit memo';
  end if;
  v_n := v_n + 1;
  line_no := v_n; gl_account_id := v_pacc.id; account_no := v_pacc.account_no; account_name := v_pacc.name;
  debit  := case when (v_type = 'purchase') = (v_total > 0) then 0 else abs(v_total) end;
  credit := case when (v_type = 'purchase') = (v_total > 0) then abs(v_total) else 0 end;
  tax_code := null; tax_base := null; line_role := 'partner';
  src_line := null; amount := null; sign := null; description := null;
  return next;
end $$;

-- ---------------------------------------------------------------------
-- VISTA PREVIA: el asiento que saldría, sin guardar nada
-- ---------------------------------------------------------------------
create or replace function erp.preview_invoice(p jsonb)
returns table (line_no int, account_no text, account_name text, debit numeric, credit numeric,
               tax_code text, tax_base numeric, line_role text)
language sql as $$
  select e.line_no, e.account_no, e.account_name, e.debit, e.credit,
         case when e.line_role = 'base' then null else e.tax_code end, e.tax_base, e.line_role
  from erp.invoice_entry_lines(p) e
  order by e.line_no nulls last;
$$;

-- ---------------------------------------------------------------------
-- REGISTRAR: factura + asiento contabilizado en una sola transacción
-- ---------------------------------------------------------------------
create or replace function erp.post_invoice(p jsonb)
returns table (invoice_id uuid, invoice_no text, entry_no int)
language plpgsql as $$
declare
  v_company   uuid := (p->>'company_id')::uuid;
  v_type      text := p->>'invoice_type';
  v_kind      text := coalesce(p->>'document_kind', 'invoice');
  v_date      date := (p->>'invoice_date')::date;
  v_posting   date := coalesce((p->>'posting_date')::date, (p->>'invoice_date')::date);
  v_ext       text := nullif(btrim(p->>'external_document_no'), '');
  v_desc      text := nullif(btrim(p->>'description'), '');
  v_corr      uuid := nullif(p->>'corrected_invoice_id', '')::uuid;
  v_corr_ref  text := nullif(btrim(p->>'corrected_reference'), '');
  v_partner   erp.business_partners;
  v_fy        erp.fiscal_years;
  v_entry     uuid;
  v_inv       uuid;
  v_no        text;
  v_seq       int;
  v_prefix    text;
  v_base      numeric;
  v_tax       numeric;
  v_entry_no  int;
  v_lines     jsonb;
  v_taxes     jsonb;
  c           erp.invoices;
begin
  if not erp.can_write(v_company) then
    raise exception 'No permission to register invoices in this company';
  end if;
  if v_date is null then
    raise exception 'The invoice date is required';
  end if;
  if v_posting < v_date then
    raise exception 'The posting date cannot be earlier than the invoice date';
  end if;
  if v_type = 'purchase' and v_ext is null then
    raise exception 'Enter the vendor invoice number';
  end if;

  select * into v_partner from erp.business_partners where id = (p->>'partner_id')::uuid and company_id = v_company;

  -- Rectificativa: debe identificar la factura que corrige (del mismo tercero y tipo)
  if v_kind = 'credit_memo' then
    if v_corr is null and v_corr_ref is null then
      raise exception 'A credit memo must identify the invoice it corrects';
    end if;
    if v_corr is not null then
      select * into c from erp.invoices where id = v_corr;
      if c.id is null or c.company_id <> v_company or c.partner_id <> v_partner.id
         or c.invoice_type <> v_type or c.document_kind <> 'invoice' then
        raise exception 'The corrected invoice must be an invoice of the same partner';
      end if;
    end if;
  end if;

  select * into v_fy from erp.fiscal_years
  where company_id = v_company and v_posting between starting_date and ending_date;
  if v_fy.id is null then
    raise exception 'No fiscal year for date %', v_posting;
  end if;

  -- Cálculo (valida líneas, cuentas, tipos y regla del lado)
  select jsonb_agg(to_jsonb(e)) into v_lines from erp.invoice_entry_lines(p) e;

  -- Numeración correlativa por serie y ejercicio (F/R ventas · C/CR compras), sin huecos
  v_prefix := case v_type || '/' || v_kind
                when 'sale/invoice' then 'F' when 'sale/credit_memo' then 'R'
                when 'purchase/invoice' then 'C' else 'CR' end;
  perform pg_advisory_xact_lock(hashtext('invoice/' || v_company || '/' || v_prefix || '/' || v_fy.year));
  select coalesce(max(split_part(i.invoice_no, '-', 3)::int), 0) + 1 into v_seq
  from erp.invoices i
  where i.company_id = v_company and i.invoice_type = v_type and i.invoice_no like v_prefix || '-' || v_fy.year || '-%';
  v_no := v_prefix || '-' || v_fy.year || '-' || lpad(v_seq::text, 4, '0');

  -- Asiento
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no)
  values (v_company, v_fy.id, v_posting,
          coalesce(v_desc, case v_kind when 'credit_memo' then 'Rectificativa ' else 'Factura ' end
                           || coalesce(v_ext, v_no) || ' · ' || v_partner.name),
          case v_type when 'sale' then v_no else v_ext end)
  returning id into v_entry;

  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, partner_id,
                                 tax_code, tax_base, description)
  select v_entry, v_company, e.line_no, e.gl_account_id, e.debit, e.credit, v_partner.id,
         case when e.line_role = 'tax' then e.tax_code end, e.tax_base, e.description
  from jsonb_to_recordset(v_lines) as e(line_no int, gl_account_id uuid, debit numeric, credit numeric,
                                        tax_code text, tax_base numeric, line_role text, description text)
  where e.line_role <> 'tax_exempt';

  v_entry_no := erp.post_entry(v_entry);

  -- Resumen por tipo de impuesto con signo (negativo si reduce: rectificativas, devoluciones…)
  select jsonb_agg(jsonb_build_object('tax_code', e.tax_code, 'tax_base', e.tax_base,
           'tax_amount', case when e.line_role = 'tax_exempt' then 0
                              when (v_type = 'purchase') = (e.debit > 0) then e.debit + e.credit
                              else -(e.debit + e.credit) end))
    into v_taxes
  from jsonb_to_recordset(v_lines) as e(tax_code text, tax_base numeric, debit numeric, credit numeric, line_role text)
  where e.line_role in ('tax', 'tax_exempt');
  select sum(x.tax_base), sum(x.tax_amount) into v_base, v_tax
  from jsonb_to_recordset(v_taxes) as x(tax_base numeric, tax_amount numeric);

  perform set_config('erp.invoice_engine', 'on', true);
  insert into erp.invoices (company_id, fiscal_year_id, invoice_type, document_kind, invoice_no, external_document_no,
                            partner_id, invoice_date, posting_date, description, corrected_invoice_id, corrected_reference,
                            total_base, total_tax, total_amount, entry_id)
  values (v_company, v_fy.id, v_type, v_kind, v_no, v_ext, v_partner.id, v_date, v_posting,
          coalesce(v_desc, ''), v_corr, v_corr_ref, v_base, v_tax, v_base + v_tax, v_entry)
  returning id into v_inv;

  insert into erp.invoice_lines (invoice_id, company_id, line_no, gl_account_id, description, amount, tax_code, sign)
  select v_inv, v_company, e.src_line, e.gl_account_id, e.description, e.amount, e.tax_code, e.sign
  from jsonb_to_recordset(v_lines) as e(src_line int, gl_account_id uuid, description text, amount numeric,
                                        tax_code text, sign int, line_role text)
  where e.line_role = 'base';

  insert into erp.invoice_tax_lines (invoice_id, company_id, tax_code, tax_base, tax_amount)
  select v_inv, v_company, x.tax_code, x.tax_base, x.tax_amount
  from jsonb_to_recordset(v_taxes) as x(tax_code text, tax_base numeric, tax_amount numeric);
  perform set_config('erp.invoice_engine', 'off', true);

  return query select v_inv, v_no, v_entry_no;
exception
  when unique_violation then
    raise exception 'Invoice % of % is already registered', v_ext, v_partner.name;
end $$;

-- ---------------------------------------------------------------------
-- El asiento de una factura no se anula suelto: se emite una rectificativa
-- (si no, la factura y su asiento dirían cosas distintas)
-- ---------------------------------------------------------------------
create or replace function erp.tg_entry_invoice_reverse()
returns trigger language plpgsql as $$
begin
  if new.reversal_of is not null and exists (select 1 from erp.invoices where entry_id = new.reversal_of) then
    raise exception 'This entry belongs to an invoice: issue a credit memo instead of reversing it';
  end if;
  return new;
end $$;

create trigger entry_invoice_reverse before insert on erp.journal_entries
  for each row execute function erp.tg_entry_invoice_reverse();

-- ---------------------------------------------------------------------
-- LIBRO REGISTRO DE FACTURAS (emitidas y recibidas), una fila por factura y tipo de impuesto
-- ---------------------------------------------------------------------
create or replace view erp.v_invoice_register with (security_invoker = true) as
select i.company_id, fy.year as fiscal_year, i.id as invoice_id, i.invoice_type, i.document_kind,
       i.invoice_no, i.external_document_no, i.invoice_date, i.posting_date,
       bp.vat_registration_no, bp.name as partner_name, bp.tax_territory,
       t.tax_code, c.tax_type, c.rate_pct, t.tax_base, t.tax_amount, t.tax_base + t.tax_amount as total,
       je.entry_no
from erp.invoices i
join erp.fiscal_years fy        on fy.id = i.fiscal_year_id
join erp.business_partners bp  on bp.id = i.partner_id
join erp.invoice_tax_lines t    on t.invoice_id = i.id
join erp.tax_codes c            on c.code = t.tax_code
join erp.journal_entries je     on je.id = i.entry_id;

-- Lista de facturas para la web
create or replace view erp.v_invoices with (security_invoker = true) as
select i.id, i.company_id, fy.year as fiscal_year, i.invoice_type, i.document_kind, i.invoice_no,
       i.external_document_no, i.invoice_date, i.posting_date, i.description,
       i.partner_id, bp.name as partner_name, bp.vat_registration_no, g.account_no as partner_account_no,
       i.total_base, i.total_tax, i.total_amount, je.entry_no,
       ci.invoice_no as corrected_invoice_no, coalesce(ci.external_document_no, i.corrected_reference) as corrected_reference
from erp.invoices i
join erp.fiscal_years fy        on fy.id = i.fiscal_year_id
join erp.business_partners bp  on bp.id = i.partner_id
left join erp.gl_accounts g     on g.id = bp.gl_account_id
join erp.journal_entries je     on je.id = i.entry_id
left join erp.invoices ci       on ci.id = i.corrected_invoice_id;

-- ---------------------------------------------------------------------
-- Seguridad
-- ---------------------------------------------------------------------
alter table erp.invoices          enable row level security;
alter table erp.invoice_lines     enable row level security;
alter table erp.invoice_tax_lines enable row level security;

create policy read  on erp.invoices for select to authenticated using (erp.can_read(company_id));
create policy write on erp.invoices for insert to authenticated with check (erp.can_write(company_id));
create policy read  on erp.invoice_lines for select to authenticated using (erp.can_read(company_id));
create policy write on erp.invoice_lines for insert to authenticated with check (erp.can_write(company_id));
create policy read  on erp.invoice_tax_lines for select to authenticated using (erp.can_read(company_id));
create policy write on erp.invoice_tax_lines for insert to authenticated with check (erp.can_write(company_id));

revoke all on erp.invoices, erp.invoice_lines, erp.invoice_tax_lines, erp.v_invoice_register, erp.v_invoices from anon, public;
grant select, insert on erp.invoices, erp.invoice_lines, erp.invoice_tax_lines to authenticated;
grant select on erp.v_invoice_register, erp.v_invoices to authenticated;

revoke execute on function erp.invoice_entry_lines(jsonb), erp.preview_invoice(jsonb), erp.post_invoice(jsonb) from anon, public;
grant execute on function erp.invoice_entry_lines(jsonb), erp.preview_invoice(jsonb), erp.post_invoice(jsonb) to authenticated;
