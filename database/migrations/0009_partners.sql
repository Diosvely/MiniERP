-- =====================================================================
-- 0009 · BUSINESS PARTNERS · Terceros: clientes, proveedores, acreedores y deudores
-- ---------------------------------------------------------------------
-- Cada tercero tiene SU subcuenta en contabilidad (estilo ERP español: ContaPlus, A3, Sage):
--   customer (cliente)   → 430xxxxx  · ventas de la actividad principal
--   vendor   (proveedor) → 400xxxxx  · compras de mercaderías y aprovisionamientos
--   creditor (acreedor)  → 410xxxxx  · servicios, suministros, profesionales…
--   debtor   (deudor)    → 440xxxxx  · otros cobros ajenos a la actividad principal
-- En BC/SAP el detalle está en la ficha del tercero y en contabilidad hay una sola cuenta
-- colectiva (posting group / reconciliation account). Aquí el detalle está en la propia subcuenta.
--
-- erp.create_partner(...)       → alta del tercero y de su subcuenta (siguiente número libre)
--                                  o vínculo con una subcuenta que ya exista (ej. importada por CSV)
-- erp.valid_spanish_tax_id(nif) → valida NIF, NIE y CIF con su letra o dígito de control
-- =====================================================================

-- ---------------------------------------------------------------------
-- Datos nuevos en la ficha del tercero
-- ---------------------------------------------------------------------
alter table erp.business_partners
  add column email        text,
  add column address      text,
  add column postal_code  text,
  add column city         text,
  add column country_code char(2) not null default 'ES',
  add column blocked      boolean not null default false;

-- Un NIF no se repite dentro del mismo tipo de tercero de una empresa (control antiduplicados).
-- El mismo NIF sí puede ser a la vez cliente y proveedor, como en la vida real.
create unique index business_partners_unique_vat
  on erp.business_partners (company_id, partner_type, vat_registration_no)
  where vat_registration_no is not null;

-- Una subcuenta solo puede pertenecer a un tercero
create unique index business_partners_unique_account
  on erp.business_partners (gl_account_id)
  where gl_account_id is not null;

-- ---------------------------------------------------------------------
-- Validación de NIF / NIE / CIF españoles
--   NIF: 8 dígitos + letra   (12345678Z)
--   NIE: X/Y/Z + 7 dígitos + letra (X1234567L)
--   CIF: letra + 7 dígitos + control (B12345674): el control es dígito o letra según el tipo de entidad
-- ---------------------------------------------------------------------
create or replace function erp.normalize_tax_id(p text)
returns text language sql immutable as $$
  select nullif(upper(regexp_replace(coalesce(p, ''), '[^A-Za-z0-9]', '', 'g')), '');
$$;

create or replace function erp.valid_spanish_tax_id(p text)
returns boolean language plpgsql immutable as $$
declare
  v       text := erp.normalize_tax_id(p);
  letters constant text := 'TRWAGMYFPDXBNJZSQVHLCKE';
  num     bigint;
  s       int := 0;
  d       int;
  c       int;
  i       int;
begin
  if v is null then return false; end if;

  -- NIF
  if v ~ '^[0-9]{8}[A-Z]$' then
    num := left(v, 8)::bigint;
    return substr(letters, (num % 23)::int + 1, 1) = right(v, 1);
  end if;

  -- NIE (X=0, Y=1, Z=2)
  if v ~ '^[XYZ][0-9]{7}[A-Z]$' then
    num := (strpos('XYZ', left(v, 1)) - 1 || substr(v, 2, 7))::bigint;
    return substr(letters, (num % 23)::int + 1, 1) = right(v, 1);
  end if;

  -- CIF
  if v ~ '^[ABCDEFGHJNPQRSUVW][0-9]{7}[0-9A-J]$' then
    for i in 1..7 loop
      d := substr(v, i + 1, 1)::int;
      if i % 2 = 1 then            -- posiciones impares: se duplica y se suman sus cifras
        d := d * 2;
        d := d / 10 + d % 10;
      end if;
      s := s + d;
    end loop;
    c := (10 - s % 10) % 10;
    if left(v, 1) in ('A', 'B', 'E', 'H') then            -- control numérico
      return right(v, 1) = c::text;
    elsif left(v, 1) in ('K', 'P', 'Q', 'S', 'N', 'W') then -- control con letra
      return right(v, 1) = substr('JABCDEFGHI', c + 1, 1);
    else                                                  -- cualquiera de los dos
      return right(v, 1) in (c::text, substr('JABCDEFGHI', c + 1, 1));
    end if;
  end if;

  return false;
end $$;

-- Cuenta colectiva del PGC según el tipo de tercero
create or replace function erp.partner_control_account(p_type text)
returns text language sql immutable as $$
  select case p_type when 'customer' then '430' when 'vendor' then '400'
                     when 'creditor' then '410' when 'debtor' then '440' end;
$$;

-- Normaliza y valida el NIF al guardar (solo terceros españoles: fuera de España el formato es libre)
create or replace function erp.tg_partner_validate()
returns trigger language plpgsql as $$
begin
  new.vat_registration_no := erp.normalize_tax_id(new.vat_registration_no);
  new.name := btrim(new.name);
  if new.name = '' then
    raise exception 'Partner name is required';
  end if;
  if new.vat_registration_no is not null
     and new.tax_territory in ('mainland', 'canary_islands', 'ceuta_melilla')
     and not erp.valid_spanish_tax_id(new.vat_registration_no) then
    raise exception 'Invalid Spanish tax ID (NIF/NIE/CIF): %', new.vat_registration_no;
  end if;
  return new;
end $$;

create trigger partner_validate
  before insert or update on erp.business_partners
  for each row execute function erp.tg_partner_validate();

-- Si se cambia el nombre del tercero, se actualiza también el de su subcuenta
create or replace function erp.tg_partner_sync_account_name()
returns trigger language plpgsql as $$
begin
  if new.gl_account_id is not null and new.name is distinct from old.name then
    update erp.gl_accounts set name = new.name where id = new.gl_account_id;
  end if;
  return new;
end $$;

create trigger partner_sync_account_name
  after update of name on erp.business_partners
  for each row execute function erp.tg_partner_sync_account_name();

-- ---------------------------------------------------------------------
-- ALTA DE TERCERO
--   p_account_no null → se crea la siguiente subcuenta libre (ej. 43000001, 43000002…)
--   p_account_no dado → debe empezar por la cuenta colectiva; si ya existe y está libre, se vincula
-- ---------------------------------------------------------------------
create or replace function erp.create_partner(
  p_company     uuid,
  p_type        text,
  p_name        text,
  p_vat_no      text default null,
  p_territory   text default null,
  p_account_no  text default null,
  p_email       text default null)
returns table (partner_id uuid, account_no text)
language plpgsql as $$
declare
  v_digits     smallint;
  v_territory  text;
  v_prefix     text := erp.partner_control_account(p_type);
  v_no         text;
  v_account    erp.gl_accounts;
  v_partner    uuid;
  v_next       bigint;
begin
  if v_prefix is null then
    raise exception 'Invalid partner type: %', p_type;
  end if;
  if not erp.can_write(p_company) then
    raise exception 'No permission to create partners in this company';
  end if;

  select posting_account_digits, tax_territory into v_digits, v_territory
  from erp.companies where id = p_company;

  -- 1) Subcuenta: la indicada o la siguiente libre
  if p_account_no is not null and btrim(p_account_no) <> '' then
    v_no := regexp_replace(p_account_no, '\s', '', 'g');
    if left(v_no, length(v_prefix)) <> v_prefix then
      raise exception 'Account % must start with % for this partner type', v_no, v_prefix;
    end if;
  else
    select coalesce(max(g.account_no::bigint), (v_prefix || repeat('0', v_digits - length(v_prefix)))::bigint) + 1
      into v_next
    from erp.gl_accounts g
    where g.company_id = p_company and g.account_type = 'posting'
      and g.account_no like v_prefix || '%' and length(g.account_no) = v_digits;
    v_no := lpad(v_next::text, v_digits, '0');
    if left(v_no, length(v_prefix)) <> v_prefix then
      raise exception 'No free accounts left under %', v_prefix;
    end if;
  end if;

  select * into v_account from erp.gl_accounts g where g.company_id = p_company and g.account_no = v_no;
  if found then
    if v_account.account_type <> 'posting' then
      raise exception 'Account % is a heading account', v_no;
    end if;
    if exists (select 1 from erp.business_partners where gl_account_id = v_account.id) then
      raise exception 'Account % already belongs to another partner', v_no;
    end if;
  else
    insert into erp.gl_accounts (company_id, account_no, name, account_type, template_account, account_category)
    values (p_company, v_no, btrim(p_name), 'posting', '', '')          -- el trigger valida y rellena la cuenta madre
    returning * into v_account;
  end if;

  -- 2) Tercero (por defecto, del mismo territorio que la empresa)
  insert into erp.business_partners (company_id, partner_type, vat_registration_no, name, tax_territory, gl_account_id, email)
  values (p_company, p_type, p_vat_no, p_name, coalesce(p_territory, v_territory), v_account.id, nullif(btrim(p_email), ''))
  returning id into v_partner;

  -- Si la subcuenta ya existía, toma el nombre del tercero
  update erp.gl_accounts set name = btrim(p_name) where id = v_account.id and name <> btrim(p_name);

  return query select v_partner, v_no;
exception
  when unique_violation then
    raise exception 'A % with tax ID % already exists in this company', p_type, erp.normalize_tax_id(p_vat_no);
end $$;

-- ---------------------------------------------------------------------
-- Al apuntar en la subcuenta de un tercero, el apunte queda vinculado a él automáticamente
-- (servirá para el libro mayor por tercero, los saldos de clientes/proveedores y el registro de facturas)
-- ---------------------------------------------------------------------
create or replace function erp.tg_line_set_partner()
returns trigger language plpgsql as $$
begin
  if new.partner_id is null then
    select id into new.partner_id from erp.business_partners where gl_account_id = new.gl_account_id;
  end if;
  return new;
end $$;

create trigger line_set_partner
  before insert on erp.journal_lines
  for each row execute function erp.tg_line_set_partner();

-- ---------------------------------------------------------------------
-- Vista para la web: terceros con su subcuenta y su saldo contabilizado
-- (saldo > 0 deudor: el cliente nos debe · saldo < 0 acreedor: debemos al proveedor)
-- ---------------------------------------------------------------------
create or replace view erp.v_partners with (security_invoker = true) as
select bp.id, bp.company_id, bp.partner_type, bp.vat_registration_no, bp.name, bp.tax_territory,
       bp.email, bp.blocked, bp.created_at,
       g.account_no,
       coalesce((select sum(l.debit - l.credit)
                 from erp.journal_lines l
                 join erp.journal_entries e on e.id = l.entry_id
                 where l.gl_account_id = bp.gl_account_id and e.status = 'posted'), 0) as balance
from erp.business_partners bp
left join erp.gl_accounts g on g.id = bp.gl_account_id;

revoke all on erp.v_partners from anon, public;
grant select on erp.v_partners to authenticated;
revoke execute on function erp.normalize_tax_id(text), erp.valid_spanish_tax_id(text),
  erp.partner_control_account(text), erp.create_partner(uuid, text, text, text, text, text, text) from anon, public;
grant execute on function erp.normalize_tax_id(text), erp.valid_spanish_tax_id(text),
  erp.partner_control_account(text), erp.create_partner(uuid, text, text, text, text, text, text) to authenticated;
