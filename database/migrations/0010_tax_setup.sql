-- =====================================================================
-- 0010 · TAX SETUP · Configuración de impuestos (IVA / IGIC) por empresa
-- ---------------------------------------------------------------------
-- Qué cuenta usa cada tipo de impuesto al contabilizar, como:
--   BC  → "VAT Posting Setup" (Purchase VAT Account / Sales VAT Account)
--   SAP → determinación de cuentas de impuesto (transacción OB40, claves VST / MWS)
--   A3 / Sage / ContaPlus → tabla de tipos de IVA con su subcuenta de soportado y repercutido
--
--   erp.tax_setup             → por tipo (VAT21, IGIC7…): subcuenta 472 (soportado) y 477 (repercutido)
--   erp.tax_settlement_setup  → por impuesto (VAT / IGIC): subcuentas de la liquidación
--                               4750 (a pagar a Hacienda) y 4700 (a devolver / compensar)
--   erp.setup_taxes(empresa)  → asistente: crea subcuentas y configuración según el territorio
--
-- Convención de subcuentas (8 dígitos):
--   4720xxxx IVA soportado    4721xxxx IGIC soportado      xxxx = tipo (0021 = 21 %, 0095 = 9,5 %)
--   4770xxxx IVA repercutido  4771xxxx IGIC repercutido
--   47500001 HP acreedora por IVA    47500002 HP Canaria acreedora por IGIC
--   47000001 HP deudora por IVA      47000002 HP Canaria deudora por IGIC
-- =====================================================================

-- ---------------------------------------------------------------------
-- Corrección de seguridad: para un usuario que NO es miembro, my_role() es null y
-- "null in (...)" da null (ni true ni false). Así, un "if not erp.can_write(...)" no saltaba
-- (la RLS sí lo frenaba después, pero con un mensaje confuso). Ahora devuelven siempre true/false.
-- ---------------------------------------------------------------------
create or replace function erp.can_write(p_company uuid)
returns boolean language sql stable as $$
  select coalesce(erp.my_role(p_company) in ('admin', 'accountant'), false)
$$;

create or replace function erp.is_admin(p_company uuid)
returns boolean language sql stable as $$
  select coalesce(erp.my_role(p_company) = 'admin', false)
$$;

-- ---------------------------------------------------------------------
-- Cuentas por tipo de impuesto
-- ---------------------------------------------------------------------
create table erp.tax_setup (
  company_id         uuid not null references erp.companies(id) on delete cascade,
  tax_code           text not null references erp.tax_codes(code),
  input_account_id   uuid references erp.gl_accounts(id),   -- 472 · impuesto soportado (compras y gastos)
  output_account_id  uuid references erp.gl_accounts(id),   -- 477 · impuesto repercutido (ventas e ingresos)
  blocked            boolean not null default false,        -- tipo que la empresa no usa
  primary key (company_id, tax_code)
);
comment on table erp.tax_setup is 'Accounts used to post each tax code (BC VAT Posting Setup / SAP OB40).';

-- ---------------------------------------------------------------------
-- Cuentas de la liquidación (modelo 303 IVA / modelo 420 IGIC)
-- ---------------------------------------------------------------------
create table erp.tax_settlement_setup (
  company_id             uuid not null references erp.companies(id) on delete cascade,
  tax_type               text not null check (tax_type in ('VAT', 'IGIC')),
  payable_account_id     uuid not null references erp.gl_accounts(id),   -- 4750 · resultado a ingresar
  receivable_account_id  uuid not null references erp.gl_accounts(id),   -- 4700 · resultado a devolver o compensar
  primary key (company_id, tax_type)
);
comment on table erp.tax_settlement_setup is 'Accounts for the periodic VAT/IGIC settlement (forms 303 / 420).';

-- ---------------------------------------------------------------------
-- Regla contable: cada cuenta debe ser una subcuenta de la empresa y colgar de la cuenta PGC correcta
-- ---------------------------------------------------------------------
create or replace function erp.check_tax_account(p_company uuid, p_account uuid, p_prefix text, p_role text)
returns void language plpgsql stable as $$
declare
  a erp.gl_accounts;
begin
  if p_account is null then return; end if;
  select * into a from erp.gl_accounts where id = p_account;
  if a.company_id is distinct from p_company then
    raise exception 'The % account does not belong to this company', p_role;
  end if;
  if a.account_type <> 'posting' then
    raise exception 'The % account % must be a posting account', p_role, a.account_no;
  end if;
  if a.account_no not like p_prefix || '%' then
    raise exception 'The % account % must start with %', p_role, a.account_no, p_prefix;
  end if;
end $$;

create or replace function erp.tg_tax_setup_validate()
returns trigger language plpgsql as $$
declare
  v_rate numeric;
begin
  select rate_pct into v_rate from erp.tax_codes where code = new.tax_code;
  perform erp.check_tax_account(new.company_id, new.input_account_id,  '472', 'input tax');
  perform erp.check_tax_account(new.company_id, new.output_account_id, '477', 'output tax');
  -- Un tipo con cuota (>0 %) necesita sus dos cuentas; los tipos 0 % y exentos no generan cuota
  if v_rate > 0 and not new.blocked and (new.input_account_id is null or new.output_account_id is null) then
    raise exception 'Tax code % needs an input (472) and an output (477) account', new.tax_code;
  end if;
  return new;
end $$;

create trigger tax_setup_validate
  before insert or update on erp.tax_setup
  for each row execute function erp.tg_tax_setup_validate();

create or replace function erp.tg_tax_settlement_validate()
returns trigger language plpgsql as $$
begin
  perform erp.check_tax_account(new.company_id, new.payable_account_id,    '4750', 'payable');
  perform erp.check_tax_account(new.company_id, new.receivable_account_id, '4700', 'receivable');
  return new;
end $$;

create trigger tax_settlement_validate
  before insert or update on erp.tax_settlement_setup
  for each row execute function erp.tg_tax_settlement_validate();

-- ---------------------------------------------------------------------
-- Asistente: configura los impuestos de la empresa en un clic
--   p_tax_type null → el impuesto de su territorio (Canarias → IGIC; resto → IVA)
--   Si una subcuenta ya existe, la reutiliza; si un tipo ya está configurado, no lo toca.
-- ---------------------------------------------------------------------
create or replace function erp.tax_rate_text(p_rate numeric)
returns text language sql immutable as $$
  select replace(trim(trailing '.' from trim(trailing '0' from p_rate::text)), '.', ',');
$$;

create or replace function erp.ensure_tax_account(
  p_company uuid, p_account_no text, p_name text, p_name_en text,
  inout status text, out account_id uuid)
language plpgsql as $$
declare
  a erp.gl_accounts;
begin
  select * into a from erp.gl_accounts where company_id = p_company and account_no = p_account_no;
  if found then
    if a.account_type <> 'posting' then
      raise exception 'Account % is a heading account', p_account_no;
    end if;
    account_id := a.id;
  else
    account_id := erp.create_posting_account(p_company, p_account_no, p_name, p_name_en);
    status := 'created';
  end if;
end $$;

create or replace function erp.setup_taxes(p_company uuid, p_tax_type text default null)
returns table (tax_code text, account_role text, account_no text, status text)
language plpgsql as $$
declare
  v_type    text;
  v_digits  smallint;
  v_territory text;
  v_tax     text;      -- 'IVA' / 'IGIC' para los nombres
  v_mid     text;      -- 0 = IVA, 1 = IGIC (4.º dígito de la subcuenta)
  t         erp.tax_codes;
  v_suffix  text;
  v_in      uuid;
  v_out     uuid;
  v_status  text;
  v_no      text;
  v_pay     uuid;
  v_rec     uuid;
begin
  if not erp.is_admin(p_company) then
    raise exception 'Only the company admin can configure taxes';
  end if;
  select posting_account_digits, tax_territory into v_digits, v_territory from erp.companies where id = p_company;
  v_type := coalesce(p_tax_type, case v_territory when 'canary_islands' then 'IGIC' else 'VAT' end);
  if v_type not in ('VAT', 'IGIC') then
    raise exception 'Invalid tax type: %', v_type;
  end if;
  v_tax := case v_type when 'VAT' then 'IVA' else 'IGIC' end;
  v_mid := case v_type when 'VAT' then '0' else '1' end;

  -- 1) Un registro por tipo vigente hoy
  for t in
    select * from erp.tax_codes c
    where c.tax_type = v_type and c.valid_from <= current_date
      and (c.valid_to is null or c.valid_to >= current_date)
    order by c.rate_pct
  loop
    if exists (select 1 from erp.tax_setup s where s.company_id = p_company and s.tax_code = t.code) then
      tax_code := t.code; account_role := null; account_no := null; status := 'existing';
      return next;
      continue;
    end if;

    v_in := null; v_out := null;
    if t.rate_pct > 0 then
      v_suffix := lpad(case when t.rate_pct = trunc(t.rate_pct) then t.rate_pct::int::text
                            else (t.rate_pct * 10)::int::text end, v_digits - 4, '0');

      v_no := '472' || v_mid || v_suffix;
      v_status := 'linked';
      select e.status, e.account_id into v_status, v_in
      from erp.ensure_tax_account(p_company, v_no,
             v_tax || ' soportado ' || erp.tax_rate_text(t.rate_pct) || '%',
             'Input ' || v_type || ' ' || trim(trailing '.' from trim(trailing '0' from t.rate_pct::text)) || '%',
             v_status) e;
      tax_code := t.code; account_role := 'input'; account_no := v_no; status := v_status;
      return next;

      v_no := '477' || v_mid || v_suffix;
      v_status := 'linked';
      select e.status, e.account_id into v_status, v_out
      from erp.ensure_tax_account(p_company, v_no,
             v_tax || ' repercutido ' || erp.tax_rate_text(t.rate_pct) || '%',
             'Output ' || v_type || ' ' || trim(trailing '.' from trim(trailing '0' from t.rate_pct::text)) || '%',
             v_status) e;
      tax_code := t.code; account_role := 'output'; account_no := v_no; status := v_status;
      return next;
    else
      tax_code := t.code; account_role := null; account_no := null; status := 'no_tax_amount';
      return next;
    end if;

    insert into erp.tax_setup (company_id, tax_code, input_account_id, output_account_id)
    values (p_company, t.code, v_in, v_out);
  end loop;

  -- 2) Cuentas de la liquidación
  if not exists (select 1 from erp.tax_settlement_setup s where s.company_id = p_company and s.tax_type = v_type) then
    v_no := '4750' || lpad(case v_type when 'VAT' then '1' else '2' end, v_digits - 4, '0');
    v_status := 'linked';
    select e.status, e.account_id into v_status, v_pay
    from erp.ensure_tax_account(p_company, v_no,
           case v_type when 'VAT' then 'Hacienda Pública, acreedora por IVA' else 'Hacienda Canaria, acreedora por IGIC' end,
           case v_type when 'VAT' then 'VAT payable' else 'IGIC payable (Canary Tax Agency)' end, v_status) e;
    tax_code := v_type; account_role := 'payable'; account_no := v_no; status := v_status;
    return next;

    v_no := '4700' || lpad(case v_type when 'VAT' then '1' else '2' end, v_digits - 4, '0');
    v_status := 'linked';
    select e.status, e.account_id into v_status, v_rec
    from erp.ensure_tax_account(p_company, v_no,
           case v_type when 'VAT' then 'Hacienda Pública, deudora por IVA' else 'Hacienda Canaria, deudora por IGIC' end,
           case v_type when 'VAT' then 'VAT receivable' else 'IGIC receivable (Canary Tax Agency)' end, v_status) e;
    tax_code := v_type; account_role := 'receivable'; account_no := v_no; status := v_status;
    return next;

    insert into erp.tax_settlement_setup (company_id, tax_type, payable_account_id, receivable_account_id)
    values (p_company, v_type, v_pay, v_rec);
  else
    tax_code := v_type; account_role := 'settlement'; account_no := null; status := 'existing';
    return next;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Al apuntar en una cuenta de impuesto configurada, el apunte toma su tipo (tax_code) automáticamente
-- (si la cuenta la comparten varios tipos, no se adivina: se deja vacío)
-- ---------------------------------------------------------------------
create or replace function erp.tg_line_set_tax_code()
returns trigger language plpgsql as $$
declare
  v_codes text[];
begin
  if new.tax_code is null then
    select array_agg(s.tax_code) into v_codes
    from erp.tax_setup s
    where s.company_id = coalesce(new.company_id, (select e.company_id from erp.journal_entries e where e.id = new.entry_id))
      and new.gl_account_id in (s.input_account_id, s.output_account_id);
    if cardinality(v_codes) = 1 then
      new.tax_code := v_codes[1];
    end if;
  end if;
  return new;
end $$;

create trigger line_set_tax_code
  before insert on erp.journal_lines
  for each row execute function erp.tg_line_set_tax_code();

-- ---------------------------------------------------------------------
-- Vistas para la web
-- ---------------------------------------------------------------------
create or replace view erp.v_tax_setup with (security_invoker = true) as
select s.company_id, s.tax_code, c.tax_type, c.rate_category, c.rate_pct,
       c.equivalence_surcharge_pct, c.description, c.description_en, s.blocked,
       s.input_account_id,  ai.account_no as input_account_no,  ai.name as input_account_name,
       s.output_account_id, ao.account_no as output_account_no, ao.name as output_account_name
from erp.tax_setup s
join erp.tax_codes c on c.code = s.tax_code
left join erp.gl_accounts ai on ai.id = s.input_account_id
left join erp.gl_accounts ao on ao.id = s.output_account_id;

create or replace view erp.v_tax_settlement_setup with (security_invoker = true) as
select s.company_id, s.tax_type,
       s.payable_account_id,    ap.account_no as payable_account_no,    ap.name as payable_account_name,
       s.receivable_account_id, ar.account_no as receivable_account_no, ar.name as receivable_account_name
from erp.tax_settlement_setup s
join erp.gl_accounts ap on ap.id = s.payable_account_id
join erp.gl_accounts ar on ar.id = s.receivable_account_id;

-- ---------------------------------------------------------------------
-- Seguridad: leen los miembros (y cualquiera en empresas demo); configura solo el admin
-- ---------------------------------------------------------------------
alter table erp.tax_setup            enable row level security;
alter table erp.tax_settlement_setup enable row level security;

create policy read   on erp.tax_setup for select to authenticated using (erp.can_read(company_id));
create policy manage on erp.tax_setup for all to authenticated
  using (erp.is_admin(company_id)) with check (erp.is_admin(company_id));
create policy read   on erp.tax_settlement_setup for select to authenticated using (erp.can_read(company_id));
create policy manage on erp.tax_settlement_setup for all to authenticated
  using (erp.is_admin(company_id)) with check (erp.is_admin(company_id));

revoke all on erp.tax_setup, erp.tax_settlement_setup, erp.v_tax_setup, erp.v_tax_settlement_setup from anon, public;
grant select, insert, update, delete on erp.tax_setup, erp.tax_settlement_setup to authenticated;
grant select on erp.v_tax_setup, erp.v_tax_settlement_setup to authenticated;

revoke execute on function erp.check_tax_account(uuid, uuid, text, text), erp.tax_rate_text(numeric),
  erp.ensure_tax_account(uuid, text, text, text, text), erp.setup_taxes(uuid, text) from anon, public;
grant execute on function erp.check_tax_account(uuid, uuid, text, text), erp.tax_rate_text(numeric),
  erp.ensure_tax_account(uuid, text, text, text, text), erp.setup_taxes(uuid, text) to authenticated;
