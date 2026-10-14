-- =====================================================================
-- 0035 · COBROS Y PAGOS CONTRA FACTURA (v0.32.0 · Tesorería I)
-- ---------------------------------------------------------------------
-- Hasta ahora un pago era un asiento manual "410 a 572": la factura no sabía si estaba pagada y la cuenta del tercero
-- solo daba un saldo, sin detalle. En SAP o Business Central el pago se hace CONTRA EL TERCERO Y SU FACTURA
-- ("liquidar" en BC, "compensar partidas abiertas" en SAP) y el ERP genera el asiento. Es además la condición para las
-- cuentas controladas (v0.33.0): si la 410 solo se va a poder mover desde Pagos, Pagos tiene que existir.
--
--   erp.payments / erp.payment_applications   el pago o cobro y a qué facturas se aplica (una o varias, total o parcial)
--   erp.post_payment(p)       registra el pago y su asiento: pago 400/410 a 57x · cobro 57x a 430/440
--   erp.link_payment(p)       vincula un asiento YA contabilizado a mano (o importado) como pago de unas facturas,
--                             sin crear otro asiento: para la contabilidad que ya existía antes de este módulo
--   erp.cancel_payment(id)    anula: contraasiento (o, si era un asiento vinculado, solo deshace el vínculo)
--   erp.open_items(empresa, fecha)   partidas abiertas: cada factura con lo pagado, lo abonado y lo pendiente
--   erp.aging(empresa, tipo, fecha)  antigüedad de saldos por tercero (no vencido, 1-30, 31-60, 61-90, +90 días)
--                                    con el saldo contable del tercero al lado: la diferencia es lo "sin vincular"
--
-- Vencimiento: cada tercero tiene sus días de pago (payment_days, como las condiciones de pago de BC); la factura
-- vence en fecha de factura + días. Las facturas anteriores a esta migración vencen en su fecha de factura.
-- Pendiente = total a pagar (total − retención) + rectificativas que la corrigen (en negativo) − cobros/pagos aplicados.
-- Re-ejecutable.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Días de pago del tercero y vencimiento de la factura
-- ---------------------------------------------------------------------
alter table erp.business_partners
  add column if not exists payment_days smallint not null default 0 check (payment_days between 0 and 365);
comment on column erp.business_partners.payment_days is
  'Days from the invoice date to the due date (0 = cash). Like the payment terms of a BC vendor / customer card.';

alter table erp.invoices add column if not exists due_date date;

create or replace function erp.tg_invoice_due_date()
returns trigger language plpgsql as $$
begin
  if new.due_date is null then
    new.due_date := new.invoice_date + coalesce((select payment_days from erp.business_partners where id = new.partner_id), 0);
  end if;
  return new;
end $$;
drop trigger if exists invoice_due_date on erp.invoices;
create trigger invoice_due_date before insert on erp.invoices
  for each row execute function erp.tg_invoice_due_date();

create or replace view erp.v_partners with (security_invoker = true) as
select bp.id, bp.company_id, bp.partner_type, bp.vat_registration_no, bp.name, bp.tax_territory,
       bp.email, bp.blocked, bp.created_at,
       g.account_no,
       coalesce((select sum(l.debit - l.credit)
                 from erp.journal_lines l
                 join erp.journal_entries e on e.id = l.entry_id
                 where l.gl_account_id = bp.gl_account_id and e.status = 'posted'), 0) as balance,
       bp.equivalence_surcharge,
       bp.legal_form,
       bp.withholding_code,
       bp.payment_days
from erp.business_partners bp
left join erp.gl_accounts g on g.id = bp.gl_account_id;

-- ---------------------------------------------------------------------
-- 2) Pagos y cobros
-- ---------------------------------------------------------------------
create table if not exists erp.payments (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null references erp.companies(id) on delete cascade,
  payment_type     text not null check (payment_type in ('payment', 'collection')),   -- pago / cobro
  partner_id       uuid not null references erp.business_partners(id),
  payment_date     date not null,
  cash_account_id  uuid references erp.gl_accounts(id),     -- 57x; vacío si es un asiento vinculado sin 57
  amount           numeric(15,2) not null check (amount > 0),
  description      text,
  entry_id         uuid not null references erp.journal_entries(id),
  linked           boolean not null default false,          -- asiento manual vinculado (no lo creó este módulo)
  cancel_entry_id  uuid references erp.journal_entries(id), -- contraasiento de la anulación
  created_by       uuid default auth.uid(),
  created_at       timestamptz not null default now()
);
create table if not exists erp.payment_applications (
  payment_id  uuid not null references erp.payments(id) on delete cascade,
  invoice_id  uuid not null references erp.invoices(id),
  company_id  uuid not null references erp.companies(id) on delete cascade,
  amount      numeric(15,2) not null check (amount > 0),
  primary key (payment_id, invoice_id)
);
comment on table erp.payments is 'Payments and collections applied to invoices (BC: apply entries · SAP: clear open items).';

create index if not exists payments_company       on erp.payments (company_id, payment_date);
create index if not exists payments_partner       on erp.payments (partner_id);
create index if not exists payments_entry         on erp.payments (entry_id);
create index if not exists payments_cash_account  on erp.payments (cash_account_id) where cash_account_id is not null;
create index if not exists payments_cancel_entry  on erp.payments (cancel_entry_id) where cancel_entry_id is not null;
create index if not exists payment_applications_invoice on erp.payment_applications (invoice_id);
create index if not exists payment_applications_company on erp.payment_applications (company_id);

-- Solo se leen desde la web: se escriben con las funciones de abajo (que comprueban permisos y reglas)
alter table erp.payments enable row level security;
alter table erp.payment_applications enable row level security;
drop policy if exists read on erp.payments;
drop policy if exists read on erp.payment_applications;
create policy read on erp.payments for select to authenticated using (erp.can_read(company_id));
create policy read on erp.payment_applications for select to authenticated using (erp.can_read(company_id));
revoke all on erp.payments, erp.payment_applications from anon, public;
grant select on erp.payments, erp.payment_applications to authenticated;

-- El asiento de un pago no se anula suelto desde el diario: se anula el pago (si no, la factura seguiría "pagada")
create or replace function erp.tg_entry_payment_reverse()
returns trigger language plpgsql as $$
begin
  if new.reversal_of is not null and coalesce(current_setting('erp.payment_engine', true), '') <> 'on'
     and exists (select 1 from erp.payments where entry_id = new.reversal_of and cancel_entry_id is null) then
    raise exception 'This entry belongs to a payment: cancel the payment instead';
  end if;
  return new;
end $$;
drop trigger if exists entry_payment_reverse on erp.journal_entries;
create trigger entry_payment_reverse before insert on erp.journal_entries
  for each row execute function erp.tg_entry_payment_reverse();

-- ---------------------------------------------------------------------
-- 3) Partidas abiertas a una fecha
-- ---------------------------------------------------------------------
create or replace function erp.open_items(p_company uuid, p_date date default null)
returns table (invoice_id uuid, invoice_type text, invoice_no text, external_document_no text,
               partner_id uuid, partner_name text, partner_account_no text,
               invoice_date date, posting_date date, due_date date,
               amount_due numeric, credited numeric, paid numeric, pending numeric,
               status text, days_overdue int)
language sql stable as $$
  with d as (select coalesce(p_date, current_date) as d),
  base as (
    select i.id, i.invoice_type, i.invoice_no, i.external_document_no, i.partner_id, bp.name, g.account_no,
           i.invoice_date, i.posting_date, coalesce(i.due_date, i.invoice_date) as due,
           i.total_amount - i.withholding_amount as due_amount,
           coalesce((select sum(c.total_amount - c.withholding_amount) from erp.invoices c
                     where c.corrected_invoice_id = i.id and c.posting_date <= d.d), 0) as credited,
           coalesce((select sum(a.amount) from erp.payment_applications a
                     join erp.payments p on p.id = a.payment_id
                     where a.invoice_id = i.id and p.payment_date <= d.d
                       and (p.cancel_entry_id is null
                            or (select ce.posting_date from erp.journal_entries ce where ce.id = p.cancel_entry_id) > d.d)), 0) as paid,
           d.d as at
    from erp.invoices i
    cross join d
    join erp.business_partners bp on bp.id = i.partner_id
    left join erp.gl_accounts g on g.id = bp.gl_account_id
    where i.company_id = p_company and i.document_kind = 'invoice' and i.posting_date <= d.d
  )
  select id, invoice_type, invoice_no, external_document_no, partner_id, name, account_no,
         invoice_date, posting_date, due,
         due_amount, credited, paid, due_amount + credited - paid,
         case when due_amount + credited - paid <= 0 then 'paid'
              when paid > 0 or credited <> 0 then 'partial' else 'pending' end,
         case when due_amount + credited - paid > 0 then greatest(at - due, 0) end
  from base;
$$;
revoke execute on function erp.open_items(uuid, date) from anon, public;
grant execute on function erp.open_items(uuid, date) to authenticated;

-- Lo que falta por pagar de una factura hoy (para validar los pagos)
create or replace function erp.invoice_pending(p_invoice uuid)
returns numeric language sql stable as $$
  select pending from erp.open_items((select company_id from erp.invoices where id = p_invoice), '9999-12-31')
  where invoice_id = p_invoice;
$$;

-- ---------------------------------------------------------------------
-- 4) Validación común de las facturas a las que se aplica un pago
-- ---------------------------------------------------------------------
create or replace function erp.check_payment_applications(p_company uuid, p_partner uuid, p_type text, p_apps jsonb)
returns numeric language plpgsql stable as $$
declare
  a      record;
  v_inv  erp.invoices;
  v_pend numeric;
  v_sum  numeric := 0;
begin
  if jsonb_typeof(p_apps) <> 'array' or jsonb_array_length(p_apps) = 0 then
    raise exception 'Choose at least one invoice to apply the payment to';
  end if;
  if (select count(*) from jsonb_array_elements(p_apps) x) <> (select count(distinct x->>'invoice_id') from jsonb_array_elements(p_apps) x) then
    raise exception 'The same invoice appears twice in the payment';
  end if;
  for a in select (x->>'invoice_id')::uuid as invoice_id, round((x->>'amount')::numeric, 2) as amount
           from jsonb_array_elements(p_apps) x loop
    select * into v_inv from erp.invoices where id = a.invoice_id and company_id = p_company;
    if not found then raise exception 'Invoice not found in this company'; end if;
    if v_inv.partner_id <> p_partner then
      raise exception 'Invoice % belongs to another partner', v_inv.invoice_no;
    end if;
    if v_inv.document_kind <> 'invoice' then
      raise exception 'Payments are applied to invoices, not to credit memos (%)', v_inv.invoice_no;
    end if;
    if v_inv.invoice_type <> (case p_type when 'payment' then 'purchase' else 'sale' end) then
      raise exception 'Invoice % is not a % invoice', v_inv.invoice_no,
        case p_type when 'payment' then 'received' else 'issued' end;
    end if;
    if a.amount is null or a.amount <= 0 then
      raise exception 'The amount applied to invoice % must be greater than zero', v_inv.invoice_no;
    end if;
    v_pend := erp.invoice_pending(a.invoice_id);
    if a.amount > v_pend then
      raise exception 'Invoice % only has % pending (you applied %)', v_inv.invoice_no, v_pend, a.amount;
    end if;
    v_sum := v_sum + a.amount;
  end loop;
  return v_sum;
end $$;

-- ---------------------------------------------------------------------
-- 5) Registrar un pago o cobro (crea el asiento)
--    p: { company_id, payment_type: payment | collection, partner_id, payment_date, cash_account_no (57…),
--         description, applications: [{ invoice_id, amount }] }
-- ---------------------------------------------------------------------
create or replace function erp.post_payment(p jsonb)
returns table (payment_id uuid, entry_no int)
language plpgsql security definer set search_path = erp, public as $$
declare
  v_company uuid := (p->>'company_id')::uuid;
  v_type    text := p->>'payment_type';
  v_date    date := (p->>'payment_date')::date;
  v_partner erp.business_partners;
  v_cash    erp.gl_accounts;
  v_fy      uuid;
  v_sum     numeric;
  v_entry   uuid;
  v_no      int;
  v_pay     uuid;
  v_docs    text;
  v_desc    text;
begin
  if not erp.can_write(v_company) then raise exception 'No permission to register payments in this company'; end if;
  if v_type is null or v_type not in ('payment', 'collection') then raise exception 'Invalid payment type: %', v_type; end if;
  if v_date is null then raise exception 'The payment date is required'; end if;

  select * into v_partner from erp.business_partners where id = (p->>'partner_id')::uuid and company_id = v_company;
  if not found then raise exception 'Choose the partner of the payment'; end if;
  if v_partner.gl_account_id is null then raise exception 'Partner % has no posting account', v_partner.name; end if;
  if v_partner.partner_type <> all ((case v_type when 'payment' then array['vendor', 'creditor'] else array['customer', 'debtor'] end)) then
    raise exception 'A % needs a %', case v_type when 'payment' then 'payment' else 'collection' end,
      case v_type when 'payment' then 'vendor or creditor' else 'customer or debtor' end;
  end if;

  select * into v_cash from erp.gl_accounts
  where company_id = v_company and account_no = p->>'cash_account_no' and account_type = 'posting';
  if not found or left(v_cash.account_no, 2) <> '57' then
    raise exception 'Choose a cash or bank account (57)';
  end if;
  if v_cash.blocked then raise exception 'Account % is blocked', v_cash.account_no; end if;

  v_sum := erp.check_payment_applications(v_company, v_partner.id, v_type, p->'applications');

  select id into v_fy from erp.fiscal_years where company_id = v_company and v_date between starting_date and ending_date;
  if v_fy is null then raise exception 'No fiscal year for date %', v_date; end if;

  select string_agg(coalesce(i.external_document_no, i.invoice_no), ', ' order by i.invoice_date, i.invoice_no) into v_docs
  from erp.invoices i where i.id in (select (x->>'invoice_id')::uuid from jsonb_array_elements(p->'applications') x);
  v_desc := coalesce(nullif(btrim(p->>'description'), ''),
                     case v_type when 'payment' then 'Pago ' else 'Cobro ' end || 'factura ' || v_docs || ' · ' || v_partner.name);

  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no)
  values (v_company, v_fy, v_date, left(v_desc, 250), left(v_docs, 60))
  returning id into v_entry;
  -- Pago: el acreedor al Debe (se le debe menos) y el banco al Haber · Cobro: al revés
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, partner_id)
  values
    (v_entry, v_company, 1, case v_type when 'payment' then v_partner.gl_account_id else v_cash.id end, v_sum, 0,
     case v_type when 'payment' then v_partner.id end),
    (v_entry, v_company, 2, case v_type when 'payment' then v_cash.id else v_partner.gl_account_id end, 0, v_sum,
     case v_type when 'collection' then v_partner.id end);
  v_no := erp.post_entry(v_entry);

  insert into erp.payments (company_id, payment_type, partner_id, payment_date, cash_account_id, amount, description, entry_id)
  values (v_company, v_type, v_partner.id, v_date, v_cash.id, v_sum, v_desc, v_entry)
  returning id into v_pay;
  insert into erp.payment_applications (payment_id, invoice_id, company_id, amount)
  select v_pay, (x->>'invoice_id')::uuid, v_company, round((x->>'amount')::numeric, 2)
  from jsonb_array_elements(p->'applications') x;

  payment_id := v_pay; entry_no := v_no;
  return next;
end $$;

-- ---------------------------------------------------------------------
-- 6) Vincular un asiento ya contabilizado (manual o importado) como pago de unas facturas, sin asiento nuevo
--    p: { company_id, entry_id, partner_id, applications: [{ invoice_id, amount }] }
--    El asiento tiene que mover la cuenta del tercero en el lado del pago (pago: Debe · cobro: Haber) por, al
--    menos, lo que se vincula (contando lo ya vinculado a ese asiento).
-- ---------------------------------------------------------------------
create or replace function erp.link_payment(p jsonb)
returns uuid
language plpgsql security definer set search_path = erp, public as $$
declare
  v_company uuid := (p->>'company_id')::uuid;
  v_e       erp.journal_entries;
  v_partner erp.business_partners;
  v_type    text;
  v_side    numeric;
  v_used    numeric;
  v_sum     numeric;
  v_cash    uuid;
  v_pay     uuid;
begin
  if not erp.can_write(v_company) then raise exception 'No permission to register payments in this company'; end if;
  select * into v_e from erp.journal_entries where id = (p->>'entry_id')::uuid and company_id = v_company;
  if not found or v_e.status <> 'posted' then raise exception 'Choose a posted entry of this company'; end if;
  if v_e.reversed_by is not null or v_e.reversal_of is not null then
    raise exception 'A reversed entry (or a reversal) cannot be linked as a payment';
  end if;
  if exists (select 1 from erp.invoices where entry_id = v_e.id)
     or exists (select 1 from erp.tax_settlements where entry_id = v_e.id)
     or exists (select 1 from erp.payments where entry_id = v_e.id and not linked) then
    raise exception 'Entry % was generated by a document: it cannot be linked as a payment', v_e.entry_no;
  end if;

  select * into v_partner from erp.business_partners where id = (p->>'partner_id')::uuid and company_id = v_company;
  if not found or v_partner.gl_account_id is null then raise exception 'Choose the partner of the payment'; end if;
  v_type := case when v_partner.partner_type in ('vendor', 'creditor') then 'payment' else 'collection' end;

  select coalesce(sum(case v_type when 'payment' then l.debit else l.credit end), 0) into v_side
  from erp.journal_lines l where l.entry_id = v_e.id and l.gl_account_id = v_partner.gl_account_id;
  select coalesce(sum(pa.amount), 0) into v_used
  from erp.payments py join erp.payment_applications pa on pa.payment_id = py.id
  where py.entry_id = v_e.id and py.cancel_entry_id is null;

  v_sum := erp.check_payment_applications(v_company, v_partner.id, v_type, p->'applications');
  if v_sum > v_side - v_used then
    raise exception 'Entry % only moves % on the account of % (% already linked)', v_e.entry_no, v_side, v_partner.name, v_used;
  end if;

  select l.gl_account_id into v_cash from erp.journal_lines l join erp.gl_accounts g on g.id = l.gl_account_id
  where l.entry_id = v_e.id and g.account_no like '57%' order by l.line_no limit 1;

  insert into erp.payments (company_id, payment_type, partner_id, payment_date, cash_account_id, amount, description, entry_id, linked)
  values (v_company, v_type, v_partner.id, v_e.posting_date, v_cash, v_sum, v_e.description, v_e.id, true)
  returning id into v_pay;
  insert into erp.payment_applications (payment_id, invoice_id, company_id, amount)
  select v_pay, (x->>'invoice_id')::uuid, v_company, round((x->>'amount')::numeric, 2)
  from jsonb_array_elements(p->'applications') x;
  return v_pay;
end $$;

-- ---------------------------------------------------------------------
-- 7) Anular un pago: contraasiento con la fecha indicada (o, si era un asiento vinculado, solo se quita el vínculo)
-- ---------------------------------------------------------------------
create or replace function erp.cancel_payment(p_payment uuid, p_date date default null, p_reason text default null)
returns integer
language plpgsql security definer set search_path = erp, public as $$
declare
  v_p   erp.payments;
  v_no  int;
begin
  select * into v_p from erp.payments where id = p_payment;
  if not found or not erp.can_write(v_p.company_id) then raise exception 'Payment not found (or no permission)'; end if;
  if v_p.cancel_entry_id is not null then raise exception 'This payment is already cancelled'; end if;

  if v_p.linked then
    delete from erp.payments where id = v_p.id;   -- el asiento manual se queda como estaba
    return null;
  end if;

  perform set_config('erp.payment_engine', 'on', true);
  v_no := erp.reverse_entry(v_p.entry_id, coalesce(p_date, v_p.payment_date), coalesce(nullif(btrim(p_reason), ''), 'Pago anulado'));
  perform set_config('erp.payment_engine', 'off', true);
  update erp.payments set cancel_entry_id = (select reversed_by from erp.journal_entries where id = v_p.entry_id)
  where id = v_p.id;
  return v_no;
end $$;

-- ---------------------------------------------------------------------
-- 8) Antigüedad de saldos por tercero a una fecha (purchase = proveedores y acreedores · sale = clientes y deudores)
--    account_balance: saldo de la subcuenta del tercero (sin los asientos de cierre y reapertura del propio ERP).
--    Si no coincide con el total pendiente, hay movimientos sin vincular a facturas (pagos a mano, saldos importados…).
-- ---------------------------------------------------------------------
create or replace function erp.aging(p_company uuid, p_type text, p_date date default null)
returns table (partner_id uuid, partner_name text, partner_account_no text, open_invoices int,
               not_due numeric, d1_30 numeric, d31_60 numeric, d61_90 numeric, d90_plus numeric,
               total numeric, account_balance numeric)
language sql stable as $$
  with d as (select coalesce(p_date, current_date) as d),
  items as (select * from erp.open_items(p_company, p_date) o where o.invoice_type = p_type and o.pending > 0),
  partners as (
    select bp.id, bp.name, g.account_no, bp.gl_account_id
    from erp.business_partners bp left join erp.gl_accounts g on g.id = bp.gl_account_id
    where bp.company_id = p_company
      and bp.partner_type = any (case p_type when 'purchase' then array['vendor', 'creditor'] else array['customer', 'debtor'] end)
  ),
  balances as (
    select pt.id, coalesce(sum(l.debit - l.credit), 0) * case p_type when 'purchase' then -1 else 1 end as balance
    from partners pt cross join d
    join erp.journal_lines l on l.gl_account_id = pt.gl_account_id
    join erp.journal_entries e on e.id = l.entry_id
    where e.status = 'posted' and e.posting_date <= d.d and e.entry_type <> 'closing'
      and not exists (select 1 from erp.year_closings yc where yc.opening_entry_id = e.id)
    group by pt.id
  )
  select pt.id, pt.name, pt.account_no,
         count(i.invoice_id)::int,
         coalesce(sum(i.pending) filter (where i.days_overdue = 0), 0),
         coalesce(sum(i.pending) filter (where i.days_overdue between 1 and 30), 0),
         coalesce(sum(i.pending) filter (where i.days_overdue between 31 and 60), 0),
         coalesce(sum(i.pending) filter (where i.days_overdue between 61 and 90), 0),
         coalesce(sum(i.pending) filter (where i.days_overdue > 90), 0),
         coalesce(sum(i.pending), 0),
         coalesce(b.balance, 0)
  from partners pt
  left join items i on i.partner_id = pt.id
  left join balances b on b.id = pt.id
  group by pt.id, pt.name, pt.account_no, b.balance
  having coalesce(sum(i.pending), 0) <> 0 or coalesce(b.balance, 0) <> 0
  order by coalesce(sum(i.pending), 0) desc, pt.name;
$$;

-- Lista de pagos para la web
create or replace view erp.v_payments with (security_invoker = true) as
select p.id, p.company_id, p.payment_type, p.partner_id, bp.name as partner_name, gp.account_no as partner_account_no,
       p.payment_date, g.account_no as cash_account_no, g.name as cash_account_name, p.amount, p.description,
       e.entry_no, fy.year as fiscal_year, p.linked, ce.entry_no as cancel_entry_no, ce.posting_date as cancel_date,
       (select string_agg(coalesce(i.external_document_no, i.invoice_no), ', ' order by i.invoice_date)
        from erp.payment_applications a join erp.invoices i on i.id = a.invoice_id where a.payment_id = p.id) as invoices
from erp.payments p
join erp.business_partners bp on bp.id = p.partner_id
left join erp.gl_accounts gp on gp.id = bp.gl_account_id
left join erp.gl_accounts g on g.id = p.cash_account_id
join erp.journal_entries e on e.id = p.entry_id
join erp.fiscal_years fy on fy.id = e.fiscal_year_id
left join erp.journal_entries ce on ce.id = p.cancel_entry_id;
revoke all on erp.v_payments from anon, public;
grant select on erp.v_payments to authenticated;

-- La lista de facturas, con su vencimiento al final (las vistas solo admiten columnas nuevas por detrás)
create or replace view erp.v_invoices with (security_invoker = true) as
select i.id, i.company_id, fy.year as fiscal_year, i.invoice_type, i.document_kind, i.invoice_no,
       i.external_document_no, i.invoice_date, i.posting_date, i.description,
       i.partner_id, bp.name as partner_name, bp.vat_registration_no, g.account_no as partner_account_no,
       i.total_base, i.total_tax, i.total_amount, je.entry_no,
       ci.invoice_no as corrected_invoice_no, coalesce(ci.external_document_no, i.corrected_reference) as corrected_reference,
       i.withholding_code, i.withholding_base, i.withholding_amount,
       i.total_amount - i.withholding_amount as amount_due,
       i.total_surcharge,
       coalesce(i.due_date, i.invoice_date) as due_date
from erp.invoices i
join erp.fiscal_years fy        on fy.id = i.fiscal_year_id
join erp.business_partners bp  on bp.id = i.partner_id
left join erp.gl_accounts g     on g.id = bp.gl_account_id
join erp.journal_entries je     on je.id = i.entry_id
left join erp.invoices ci       on ci.id = i.corrected_invoice_id;

-- El diario sabe qué asientos vienen de un pago o cobro
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

-- ---------------------------------------------------------------------
-- 9) Borrar una empresa por tandas (0029): los pagos apuntan a asientos, se borran antes
-- ---------------------------------------------------------------------
create or replace function erp.delete_company_step(p_company uuid, p_batch int default 5000)
returns integer language plpgsql security definer set search_path = erp, public as $$
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
end $$;

-- ---------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------
revoke execute on function erp.post_payment(jsonb), erp.link_payment(jsonb), erp.cancel_payment(uuid, date, text),
  erp.aging(uuid, text, date), erp.invoice_pending(uuid), erp.check_payment_applications(uuid, uuid, text, jsonb)
  from anon, public;
grant execute on function erp.post_payment(jsonb), erp.link_payment(jsonb), erp.cancel_payment(uuid, date, text),
  erp.aging(uuid, text, date), erp.invoice_pending(uuid), erp.check_payment_applications(uuid, uuid, text, jsonb)
  to authenticated;
