-- =====================================================================
-- 0063 · FINANCIACIÓN INTEGRADA: la factura de la cuota del leasing, la ficha del activo, el cierre, el auditor,
--        las cuentas controladas, el glosario y los supuestos · v0.43.0
-- ---------------------------------------------------------------------
--   · Leasing (NRV 8.ª): el alta crea también la ficha del activo en Inmovilizado (su amortización es la de siempre).
--     La cuota se registra como FACTURA RECIBIDA de la entidad, con su IGIC / IVA (lo exige la ley del impuesto: el
--     arrendamiento financiero es una prestación de servicios), desde Financiación:
--       5240 (principal) + 1740 (si no se reclasificó) + 527 (intereses ya devengados) + 6623 (el resto) + 472 / 410.
--     Solo así se aceptan esas cuentas en una factura; deshacerla emite la rectificativa completa.
--   · Asistente de cierre: paso nuevo «Financiación» (intereses devengados y reclasificación a corto), antes del
--     auditor: 9 financing · 10 audit_checks · 11 corporate_tax · 12 close.
--   · Auditor: «financing_ledger»: las cuentas de los préstamos frente a lo que ha contabilizado el módulo.
--   · Cuentas controladas: 170, 171, 174, 520, 521, 524, 527 y 528.
--   · Glosario: «Coste amortizado», «Tipo de interés efectivo», «Arrendamiento financiero» y «Deuda a corto y a largo».
--   · Catálogo de operaciones y Practicar: el préstamo y el leasing, con dos supuestos.
-- Re-ejecutable.
-- =====================================================================

-- 1) El leasing y su ficha de Inmovilizado; la factura de cada cuota y su rectificativa
alter table erp.loans add column if not exists asset_id uuid references erp.fixed_assets(id);
create index if not exists loans_asset_idx on erp.loans (asset_id);
alter table erp.loan_events add column if not exists cancel_invoice_id uuid references erp.invoices(id);
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'loan_events_invoice_id_fkey') then
    alter table erp.loan_events add constraint loan_events_invoice_id_fkey foreign key (invoice_id) references erp.invoices(id);
  end if;
end $$;
create index if not exists loan_events_invoice_idx on erp.loan_events (invoice_id);
create index if not exists loan_events_cancel_invoice_idx on erp.loan_events (cancel_invoice_id);

-- 2) Alta (versión de la 0062 con la ficha del activo del leasing): p = lo de la 0062 + leasing { useful_life_months,
--    residual_value?, class_code?, asset_name?, asset_start_date? (la puesta en funcionamiento) }
create or replace function erp.loan_create(p jsonb)
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare
  v_company uuid := (p->>'company_id')::uuid; c jsonb; v_code text; v_id uuid; v_type text := coalesce(p->>'lender_type', 'bank');
  v_desc text := nullif(btrim(p->>'description'), ''); a_long uuid; a_short uuid; a_int uuid; a_acc uuid; a_bank uuid; a_asset uuid;
  v_short numeric; v_long numeric; v_entry uuid; v_asset uuid; v_asset_code text; v_warn jsonb;
begin
  c := erp.loan_calc(p);
  perform erp.loan_check(v_company, (c->>'start_date')::date);
  if v_desc is null then raise exception 'The description is required'; end if;
  if v_type not in ('bank', 'other') then raise exception 'Invalid lender type: %', v_type; end if;
  -- v0.43.0 (0063): el leasing da de alta también la ficha del activo, con su vida útil
  if c->>'kind' = 'leasing' and coalesce((p->>'useful_life_months')::int, 0) <= 0 then
    raise exception 'The useful life of the leased asset is required (months)';
  end if;
  if c->>'kind' = 'loan' then
    a_long  := erp.loan_account(v_company, p->>'long_account_no', case v_type when 'bank' then '1700' else '1710' end,
                 case v_type when 'bank' then 'Préstamos a largo plazo de entidades de crédito' else 'Deudas a largo plazo' end, '^17[01]');
    a_short := erp.loan_account(v_company, p->>'short_account_no', case v_type when 'bank' then '5200' else '5210' end,
                 case v_type when 'bank' then 'Préstamos a corto plazo de entidades de crédito' else 'Deudas a corto plazo' end, '^52[01]');
    a_bank  := erp.equity_bank(v_company, p->>'bank_account_no');
  else
    a_long  := erp.loan_account(v_company, p->>'long_account_no', '1740', 'Acreedores por arrendamiento financiero a largo plazo', '^174');
    a_short := erp.loan_account(v_company, p->>'short_account_no', '5240', 'Acreedores por arrendamiento financiero a corto plazo', '^524');
    a_asset := erp.loan_account(v_company, p->>'asset_account_no', '213', 'Maquinaria', '^2[01]');
    if nullif(btrim(p->>'bank_account_no'), '') is not null then a_bank := erp.equity_bank(v_company, p->>'bank_account_no'); end if;
  end if;
  a_int := erp.loan_account(v_company, p->>'interest_account_no', case v_type when 'bank' then '6623' else '6624' end,
             case v_type when 'bank' then 'Intereses de deudas con entidades de crédito' else 'Intereses de deudas con otras empresas' end, '^662');
  a_acc := erp.adjust_account(v_company, case v_type when 'bank' then '527' else '528' end,
             case v_type when 'bank' then 'Intereses a corto plazo de deudas con entidades de crédito' else 'Intereses a corto plazo de deudas' end);
  select 'FIN-' || lpad((count(*) + 1)::text, 4, '0') into v_code from erp.loans where company_id = v_company;
  insert into erp.loans (company_id, code, kind, description, lender, lender_type, start_date, first_due_date, frequency, periods,
                         nominal_rate, principal, costs, net_amount, instalment, purchase_option, fair_value, present_value,
                         effective_rate, effective_rate_year, long_account_id, short_account_id, interest_account_id,
                         accrued_account_id, bank_account_id, asset_account_id, data)
  values (v_company, v_code, c->>'kind', v_desc, coalesce(btrim(p->>'lender'), ''), v_type, (c->>'start_date')::date, (c->>'first_due_date')::date,
          (c->>'frequency')::int, (c->>'periods')::int, (c->>'nominal_rate')::numeric, (c->>'principal')::numeric, (c->>'costs')::numeric,
          (c->>'net_amount')::numeric, (c->>'instalment')::numeric, (c->>'purchase_option')::numeric, (c->>'fair_value')::numeric,
          (c->>'present_value')::numeric, (c->>'effective_rate')::numeric, (c->>'effective_rate_year')::numeric,
          a_long, a_short, a_int, a_acc, a_bank, a_asset, p - 'company_id')
  returning id into v_id;
  insert into erp.loan_schedule (loan_id, company_id, n, due_date, payment, interest, reduction, balance)
  select v_id, v_company, (x->>'n')::int, (x->>'due_date')::date, (x->>'payment')::numeric, (x->>'interest')::numeric,
         (x->>'reduction')::numeric, (x->>'balance')::numeric
  from jsonb_array_elements(c->'schedule') x;
  v_short := (c->>'short_part')::numeric; v_long := (c->>'net_amount')::numeric - v_short;
  v_entry := erp.equity_entry(v_company, (c->>'start_date')::date,
               case c->>'kind' when 'loan' then 'Préstamo · cobro' else 'Arrendamiento financiero · alta del activo' end || ' · ' || v_desc, v_code,
               jsonb_build_array(erp.equity_line(coalesce(a_asset, a_bank), (c->>'net_amount')::numeric, 0),
                                 erp.equity_line(a_short, 0, v_short), erp.equity_line(a_long, 0, v_long)));
  insert into erp.loan_events (loan_id, company_id, kind, event_date, amount, short_part, long_part, entry_id)
  values (v_id, v_company, 'start', (c->>'start_date')::date, (c->>'net_amount')::numeric, v_short, v_long, v_entry);
  if c->>'kind' = 'leasing' then
    select f.asset_id, f.code, f.warnings into v_asset, v_asset_code, v_warn
    from erp.create_fixed_asset(jsonb_build_object('company_id', v_company, 'name', coalesce(nullif(btrim(p->>'asset_name'), ''), v_desc),
           'asset_account_no', (select account_no from erp.gl_accounts where id = a_asset), 'class_code', nullif(p->>'class_code', ''),
           'acquisition_date', c->>'start_date', 'start_date', coalesce(nullif(p->>'asset_start_date', ''), c->>'start_date'),
           'cost', c->>'net_amount', 'residual_value', coalesce((p->>'residual_value')::numeric, 0),
           'useful_life_months', (p->>'useful_life_months')::int)) f;
    update erp.loans set asset_id = v_asset where id = v_id;
  end if;
  return (c - 'schedule') || jsonb_build_object('loan_id', v_id, 'code', v_code,
    'entry_no', (select entry_no from erp.journal_entries where id = v_entry), 'asset_code', v_asset_code, 'asset_warnings', v_warn);
end $$;


-- 3) La factura de la cuota del leasing: p = { loan_id, partner_id (la entidad: un acreedor o proveedor),
--    external_document_no (su número de factura), invoice_date? (por defecto, el vencimiento), posting_date?,
--    tax_code (IGIC7, IVA21…), description? }. Las líneas salen del cuadro (loan_next_instalment): lo que baja la deuda
--    (5240 y, si no se reclasificó, 1740), los intereses ya devengados (527 / 528) y el resto de intereses (6623). La
--    base del impuesto es la cuota entera.
create or replace function erp.loan_instalment_invoice(p jsonb)
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare
  l erp.loans; x jsonb; v_date date; v_post date; v_lines jsonb := '[]'; v_tax text := nullif(btrim(p->>'tax_code'), '');
  v_inv uuid; v_no text; v_entry_no int; v_entry uuid; v_desc text;
begin
  select * into l from erp.loans where id = (p->>'loan_id')::uuid;
  if not found then raise exception 'Loan not found'; end if;
  if not erp.can_write(l.company_id) then raise exception 'No permission to post loans in this company'; end if;
  if l.kind <> 'leasing' then raise exception 'Only a finance lease instalment is registered as an invoice: post the loan payment instead'; end if;
  if l.status <> 'active' then raise exception 'The loan is not active (%)', l.status; end if;
  if v_tax is null then raise exception 'Choose the tax code of the instalment (the leasing company charges VAT / IGIC)'; end if;
  x := erp.loan_next_instalment(l.id);
  v_date := coalesce((p->>'invoice_date')::date, (x->>'due_date')::date);
  v_post := coalesce((p->>'posting_date')::date, v_date);
  perform erp.loan_check(l.company_id, v_post);
  if v_post < (select max(event_date) from erp.loan_events where loan_id = l.id and status = 'posted') then
    raise exception 'The date is earlier than the last posting of this loan';
  end if;
  v_desc := 'Cuota ' || (x->>'n') || '/' || l.periods || case when (x->>'purchase_option')::numeric > 0 then ' y opción de compra' else '' end
            || ' · ' || l.description;
  if (x->>'short_part')::numeric > 0 then
    v_lines := v_lines || jsonb_build_object('account_no', x->>'short_account_no', 'amount', x->'short_part', 'tax_code', v_tax, 'description', 'Principal');
  end if;
  if (x->>'long_part')::numeric > 0 then
    v_lines := v_lines || jsonb_build_object('account_no', x->>'long_account_no', 'amount', x->'long_part', 'tax_code', v_tax, 'description', 'Principal (largo plazo)');
  end if;
  if (x->>'accrued_used')::numeric > 0 then
    v_lines := v_lines || jsonb_build_object('account_no', x->>'accrued_account_no', 'amount', x->'accrued_used', 'tax_code', v_tax, 'description', 'Intereses devengados');
  end if;
  if (x->>'interest_expense')::numeric > 0 then
    v_lines := v_lines || jsonb_build_object('account_no', x->>'interest_account_no', 'amount', x->'interest_expense', 'tax_code', v_tax, 'description', 'Intereses');
  end if;
  perform set_config('erp.loan_engine', 'on', true);
  select r.invoice_id, r.invoice_no, r.entry_no into v_inv, v_no, v_entry_no
  from erp.post_invoice(jsonb_build_object('company_id', l.company_id, 'invoice_type', 'purchase', 'document_kind', 'invoice',
    'partner_id', p->'partner_id', 'external_document_no', p->'external_document_no', 'invoice_date', v_date, 'posting_date', v_post,
    'description', coalesce(nullif(btrim(p->>'description'), ''), v_desc), 'lines', v_lines)) r;
  perform set_config('erp.loan_engine', 'off', true);
  select entry_id into v_entry from erp.invoices where id = v_inv;
  insert into erp.loan_events (loan_id, company_id, kind, event_date, n, amount, interest, accrued_used, short_part, long_part, entry_id, invoice_id)
  values (l.id, l.company_id, 'payment', v_post, (x->>'n')::int, (x->>'payment')::numeric, (x->>'interest_expense')::numeric,
          (x->>'accrued_used')::numeric, (x->>'short_part')::numeric, (x->>'long_part')::numeric, v_entry, v_inv);
  if (x->>'n')::int = l.periods then update erp.loans set status = 'repaid' where id = l.id; end if;
  return x || jsonb_build_object('invoice_id', v_inv, 'invoice_no', v_no, 'entry_no', v_entry_no, 'date', v_post);
end $$;

-- Una rectificativa de la factura de una cuota solo la emite Financiación (al deshacer la cuota): si no, el cuadro y
-- la contabilidad dejarían de coincidir
create or replace function erp.tg_invoice_loan_credit_memo()
returns trigger language plpgsql security definer set search_path = erp, public as $$
begin
  if new.corrected_invoice_id is not null and coalesce(current_setting('erp.loan_engine', true), '') <> 'on'
     and exists (select 1 from erp.loan_events v where v.invoice_id = new.corrected_invoice_id) then
    raise exception 'This invoice is a finance lease instalment: undo it from Financing (it issues the credit memo)';
  end if;
  return new;
end $$;
drop trigger if exists invoice_loan_credit_memo on erp.invoices;
create trigger invoice_loan_credit_memo before insert on erp.invoices for each row execute function erp.tg_invoice_loan_credit_memo();

revoke execute on function erp.loan_instalment_invoice(jsonb), erp.tg_invoice_loan_credit_memo() from anon, public;
grant execute on function erp.loan_instalment_invoice(jsonb) to authenticated;

-- 4) Deshacer el último movimiento (versión de la 0062 con la cuota del leasing y la ficha del activo)
create or replace function erp.loan_cancel(p_loan uuid)
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare l erp.loans; ev erp.loan_events; inv erp.invoices; v_cm uuid; a erp.fixed_assets;
begin
  select * into l from erp.loans where id = p_loan;
  if not found then raise exception 'Loan not found'; end if;
  if not erp.can_write(l.company_id) then raise exception 'No permission to change loans in this company'; end if;
  perform pg_advisory_xact_lock(hashtext('loans/' || l.company_id));
  select * into ev from erp.loan_events where loan_id = p_loan and status = 'posted' order by seq desc limit 1;
  if not found then raise exception 'The loan is already cancelled'; end if;
  if exists (select 1 from erp.fiscal_years f where f.company_id = l.company_id and ev.event_date between f.starting_date and f.ending_date and f.status = 'closed') then
    raise exception 'The year of this posting is closed: reopen it first';
  end if;
  if ev.invoice_id is not null then
    -- v0.43.0 (0063): la cuota del leasing es una factura; se deshace con su rectificativa completa (mismas líneas)
    select * into inv from erp.invoices where id = ev.invoice_id;
    perform set_config('erp.loan_engine', 'on', true);
    select x.invoice_id into v_cm from erp.post_invoice(jsonb_build_object(
      'company_id', inv.company_id, 'invoice_type', 'purchase', 'document_kind', 'credit_memo', 'partner_id', inv.partner_id,
      'invoice_date', inv.posting_date, 'posting_date', inv.posting_date, 'external_document_no', inv.external_document_no || '-ANUL',
      'corrected_invoice_id', inv.id, 'description', 'Anulación de la cuota · ' || l.description,
      'lines', (select jsonb_agg(jsonb_build_object('account_no', g.account_no, 'amount', il.amount, 'tax_code', il.tax_code,
                                                    'description', il.description) order by il.line_no)
                from erp.invoice_lines il join erp.gl_accounts g on g.id = il.gl_account_id where il.invoice_id = inv.id))) x;
    perform set_config('erp.loan_engine', 'off', true);
    update erp.loan_events set status = 'cancelled', cancel_invoice_id = v_cm where id = ev.id;
  else
    if ev.kind = 'start' and l.asset_id is not null then
      -- v0.43.0 (0063): sin amortizaciones ni deterioros, la ficha del activo se borra con el alta
      select * into a from erp.fixed_assets where id = l.asset_id;
      if a.status <> 'active' or exists (select 1 from erp.asset_depreciations d where d.asset_id = a.id)
         or exists (select 1 from erp.asset_events x where x.asset_id = a.id) then
        raise exception 'Asset % already has depreciation or other postings: undo them in Fixed assets first', a.code;
      end if;
      update erp.loans set asset_id = null where id = l.id;
      delete from erp.fixed_assets where id = a.id;
    end if;
    if ev.entry_id is not null then perform erp.adjust_reverse(ev.entry_id, ev.event_date, 'Deshacer ' || l.code); end if;
    update erp.loan_events set status = 'cancelled' where id = ev.id;
  end if;
  update erp.loans set status = case when ev.kind = 'start' then 'cancelled' else 'active' end where id = l.id;
  return jsonb_build_object('code', l.code, 'kind', ev.kind, 'n', ev.n, 'date', ev.event_date,
    'credit_memo_no', (select invoice_no from erp.invoices where id = v_cm));
end $$;

-- 5) Líneas de una factura (versión de la 0061 con la cuota del leasing)
CREATE OR REPLACE FUNCTION erp.invoice_entry_lines(p jsonb)
 RETURNS TABLE(line_no integer, gl_account_id uuid, account_no text, account_name text, debit numeric, credit numeric, tax_code text, tax_base numeric, line_role text, src_line integer, amount numeric, sign integer, description text)
 LANGUAGE plpgsql
 STABLE
AS $function$
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
  v_comp      erp.companies;
  v_wh_code   text := nullif(btrim(p->>'withholding_code'), '');
  v_wh        erp.withholding_codes;
  v_whs       erp.withholding_setup;
  v_base_total numeric := 0;
  v_wh_amt    numeric := 0;
  v_nd        boolean;              -- compras de un comerciante en recargo de equivalencia: nada es deducible
  v_re        numeric;
  v_side_acc  uuid;
  v_posting   date := coalesce(nullif(p->>'posting_date', ''), p->>'invoice_date')::date;
  v_pr        numeric;              -- prorrata provisional del año (null = deducción total)
  v_ded       numeric;
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

  select * into v_comp from erp.companies c where c.id = v_company;
  v_nd := v_comp.vat_regime = 'equivalence_surcharge' and v_type = 'purchase';

  -- Retención IRPF (opcional): debe existir y estar configurada en la empresa
  if v_wh_code is not null then
    select * into v_wh from erp.withholding_codes w where w.code = v_wh_code;
    if not found then
      raise exception 'Unknown withholding code %', v_wh_code;
    end if;
    select * into v_whs from erp.withholding_setup ws where ws.company_id = v_company and ws.withholding_code = v_wh_code;
    if not found or v_whs.blocked then
      raise exception 'Withholding % is not set up for this company (Taxes tab)', v_wh_code;
    end if;
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
    -- v0.42.0: también la 113 (gastos de constitución o de ampliación de capital, que van contra reservas: NRV 9.ª)
    -- v0.43.0: la cuota de un leasing (desde Financiación): 174 / 524 (principal) y 527 / 528 (intereses devengados)
    if v_type = 'purchase' and a.account_no ~ '^(174|524|527|528)' and coalesce(current_setting('erp.loan_engine', true), '') <> 'on' then
      raise exception 'Line %: account % belongs to a finance lease: register the instalment invoice from Financing', r.n, a.account_no;
    end if;
    if v_type = 'purchase' and left(a.account_no, 1) not in ('2', '6') and a.account_no not like '113%'
       and not (a.account_no ~ '^(174|524|527|528)' and coalesce(current_setting('erp.loan_engine', true), '') = 'on') then
      raise exception 'Line %: account % is not valid in a received invoice (use group 6 or 2, or 113 for incorporation or capital increase costs)', r.n, a.account_no;
    end if;
    -- v0.35.0: la venta de un inmovilizado se factura a su cuenta (20x / 21x / 22x); la baja la hace el módulo
    if v_type = 'sale' and left(a.account_no, 1) <> '7' and left(a.account_no, 2) not in ('20', '21', '22') then
      raise exception 'Line %: account % is not valid in an issued invoice (use group 7, or the asset account to sell a fixed asset)', r.n, a.account_no;
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

    -- Operaciones sin cuota: cada causa tiene sus condiciones (lo que comprobaría un inspector)
    if tc.rate_category in ('export', 'intra_eu') and v_type <> 'sale' then
      raise exception 'Line %: % (export / intra-EU supply) is only for issued invoices', r.n, r.code;
    end if;
    if tc.rate_category = 'intra_eu' and v_partner.tax_territory <> 'eu' then
      raise exception 'Line %: an intra-EU supply (%) needs a customer from another EU country', r.n, r.code;
    end if;
    if tc.rate_category = 'export' and v_comp.tax_territory = 'mainland' and v_partner.tax_territory = 'eu' then
      raise exception 'Line %: a sale of goods to another EU country is an intra-EU supply, not an export', r.n;
    end if;
    if tc.rate_category in ('export', 'not_subject') and v_partner.tax_territory = v_comp.tax_territory then
      raise exception 'Line %: % is only for partners outside the company tax territory (%)', r.n, r.code, v_comp.tax_territory;
    end if;

    -- Inversión del sujeto pasivo y adquisición intracomunitaria: solo en compras
    if tc.rate_category in ('reverse_charge', 'intra_eu_acquisition') and v_type <> 'purchase' then
      raise exception 'Line %: % (reverse charge) is only for received invoices', r.n, r.code;
    end if;
    if tc.rate_category = 'intra_eu_acquisition' and v_partner.tax_territory <> 'eu' then
      raise exception 'Line %: an intra-EU acquisition (%) needs a vendor from another EU country', r.n, r.code;
    end if;
    if tc.rate_category in ('reverse_charge', 'intra_eu_acquisition') and v_comp.vat_regime = 'equivalence_surcharge' then
      raise exception 'Line %: reverse charge is not available for a retailer under the equivalence surcharge in this lab', r.n;
    end if;
    -- Recargo de equivalencia: el minorista vende con el IVA incluido en el precio (no lo liquida)
    if tc.rate_category = 'retail_surcharge' and not (v_comp.vat_regime = 'equivalence_surcharge' and v_type = 'sale') then
      raise exception 'Line %: % is only for sales of a retailer under the equivalence surcharge', r.n, r.code;
    end if;
    if v_comp.vat_regime = 'equivalence_surcharge' and v_type = 'sale' and tc.rate_pct > 0 then
      raise exception 'Line %: a retailer under the equivalence surcharge records its sales with VAT included (code VAT_RE_INC)', r.n;
    end if;
    if v_type = 'sale' and v_partner.equivalence_surcharge and tc.equivalence_surcharge_pct is not null
       and s.surcharge_account_id is null then
      raise exception 'Line %: the equivalence surcharge account for % is not set up (Taxes: run the setup again)', r.n, r.code;
    end if;

    -- Regla del lado: reducen las cuentas 606/608/609 · 706/708/709 y todas las líneas de una rectificativa
    v_sign := case when v_kind = 'credit_memo'
                     or a.template_account in ('606', '608', '609', '706', '708', '709') then -1 else 1 end;

    v_work := v_work || jsonb_build_object(
      'n', r.n, 'gl_account_id', a.id, 'account_no', a.account_no, 'account_name', a.name,
      'amount', round(r.amount_txt::numeric, 2), 'tax_code', r.code, 'sign', v_sign, 'rate', tc.rate_pct,
      'description', r.descr,
      'cat', tc.rate_category, 're_pct', tc.equivalence_surcharge_pct, 'ttype', tc.tax_type,
      'in_acc', s.input_account_id, 'out_acc', s.output_account_id, 're_acc', s.surcharge_account_id);
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

  v_base_total := v_total;   -- base imponible neta de la factura (con signo)

  -- 2) Cuotas: una por tipo, sobre la base neta de la factura, redondeada a céntimos
  for t in
    select w.tax_code as code, max(w.rate) as rate, max(w.re_pct) as re_pct, max(w.cat) as cat, max(w.ttype) as ttype,
           sum(w.sign * w.amount) as base,
           (array_agg(w.in_acc))[1] as in_acc, (array_agg(w.out_acc))[1] as out_acc, (array_agg(w.re_acc))[1] as re_acc,
           (array_agg(w.gl_account_id order by w.n))[1] as first_acc
    from jsonb_to_recordset(v_work) as w(n int, tax_code text, rate numeric, re_pct numeric, cat text, ttype text, sign int,
                                         amount numeric, in_acc uuid, out_acc uuid, re_acc uuid, gl_account_id uuid)
    group by w.tax_code order by w.tax_code
  loop
    v_signed := round(t.base * t.rate / 100, 2);
    src_line := null; amount := null; sign := null; description := null;
    tax_code := t.code; tax_base := t.base;

    if v_signed = 0 then
      -- tipo 0 % o sin cuota: no hay apunte, pero sí base para el libro registro
      line_no := null; gl_account_id := null; account_no := null; account_name := null;
      debit := 0; credit := 0; line_role := 'tax_exempt';
      return next;
      continue;
    end if;

    -- Prorrata: en las compras solo se deduce el porcentaje provisional del año; el resto es más coste
    v_pr := null;
    if v_type = 'purchase' and not v_nd then
      select pr.provisional_pct into v_pr from erp.pro_rata pr
      where pr.company_id = v_company and pr.tax_type = t.ttype and pr.year = extract(year from v_posting);
    end if;
    v_ded := case when v_pr is null then v_signed else round(v_signed * v_pr / 100, 2) end;

    if t.cat in ('reverse_charge', 'intra_eu_acquisition') then
      -- ISP / adquisición intracomunitaria: la EMPRESA se repercute y se soporta la cuota.
      -- 472 al Debe y 477 al Haber por el mismo importe; el proveedor no la cobra (no suma al total)
      if v_ded <> 0 then
        v_n := v_n + 1;
        line_no := v_n; gl_account_id := t.in_acc;
        select g.account_no, g.name into account_no, account_name from erp.gl_accounts g where g.id = t.in_acc;
        debit  := case when v_ded > 0 then v_ded else 0 end;
        credit := case when v_ded > 0 then 0 else -v_ded end;
        line_role := 'tax';
        return next;
      end if;
      if v_signed - v_ded <> 0 then   -- parte no deducible por la prorrata: a la cuenta de la compra
        v_n := v_n + 1;
        line_no := v_n; gl_account_id := t.first_acc;
        select g.account_no, g.name into account_no, account_name from erp.gl_accounts g where g.id = t.first_acc;
        debit  := case when v_signed - v_ded > 0 then v_signed - v_ded else 0 end;
        credit := case when v_signed - v_ded > 0 then 0 else v_ded - v_signed end;
        line_role := 'tax_nd';
        return next;
      end if;
      v_n := v_n + 1;
      line_no := v_n; gl_account_id := t.out_acc;
      select g.account_no, g.name into account_no, account_name from erp.gl_accounts g where g.id = t.out_acc;
      debit  := case when v_signed > 0 then 0 else -v_signed end;
      credit := case when v_signed > 0 then v_signed else 0 end;
      line_role := 'tax_rc';
      return next;
      continue;
    end if;

    v_total := v_total + v_signed;
    if v_pr is not null then
      -- Prorrata: 472 por la parte deducible y la cuenta de la compra por el resto
      if v_ded <> 0 then
        v_n := v_n + 1;
        line_no := v_n; gl_account_id := t.in_acc;
        select g.account_no, g.name into account_no, account_name from erp.gl_accounts g where g.id = t.in_acc;
        debit  := case when v_ded > 0 then v_ded else 0 end;
        credit := case when v_ded > 0 then 0 else -v_ded end;
        line_role := 'tax';
        return next;
      end if;
      if v_signed - v_ded <> 0 then
        v_n := v_n + 1;
        line_no := v_n; gl_account_id := t.first_acc;
        select g.account_no, g.name into account_no, account_name from erp.gl_accounts g where g.id = t.first_acc;
        debit  := case when v_signed - v_ded > 0 then v_signed - v_ded else 0 end;
        credit := case when v_signed - v_ded > 0 then 0 else v_ded - v_signed end;
        line_role := 'tax_nd';
        return next;
      end if;
    else
      -- Cuota normal (o no deducible: comerciante en recargo de equivalencia → mayor coste, a la cuenta de la compra)
      v_side_acc := case when v_nd then t.first_acc when v_type = 'purchase' then t.in_acc else t.out_acc end;
      v_n := v_n + 1;
      line_no := v_n; gl_account_id := v_side_acc;
      select g.account_no, g.name into account_no, account_name from erp.gl_accounts g where g.id = v_side_acc;
      debit  := case when (v_type = 'purchase') = (v_signed > 0) then abs(v_signed) else 0 end;
      credit := case when (v_type = 'purchase') = (v_signed > 0) then 0 else abs(v_signed) end;
      line_role := case when v_nd then 'tax_nd' else 'tax' end;
      return next;
    end if;

    -- Recargo de equivalencia: lo cobra el mayorista al minorista (477 recargo) y el minorista lo paga sin deducirlo
    if t.re_pct is not null and (v_nd or (v_type = 'sale' and v_partner.equivalence_surcharge)) then
      v_re := round(t.base * t.re_pct / 100, 2);
      if v_re <> 0 then
        v_total := v_total + v_re;
        v_side_acc := case when v_nd then t.first_acc else t.re_acc end;
        v_n := v_n + 1;
        line_no := v_n; gl_account_id := v_side_acc;
        select g.account_no, g.name into account_no, account_name from erp.gl_accounts g where g.id = v_side_acc;
        debit  := case when (v_type = 'purchase') = (v_re > 0) then abs(v_re) else 0 end;
        credit := case when (v_type = 'purchase') = (v_re > 0) then 0 else abs(v_re) end;
        line_role := case when v_nd then 'surcharge_nd' else 'surcharge' end;
        return next;
      end if;
    end if;
  end loop;

  -- 3) Retención IRPF sobre la base imponible (sin el impuesto):
  --    compras → 4751 al HABER (la empresa la retiene y la ingresa en Hacienda: modelos 111 / 115)
  --    ventas  → 473 al DEBE (el cliente nos la retiene: es un pago a cuenta de nuestro impuesto)
  if v_wh_code is not null then
    v_wh_amt := round(v_base_total * v_wh.rate_pct / 100, 2);
    if v_wh_amt <> 0 then
      v_n := v_n + 1;
      line_no := v_n;
      gl_account_id := case v_type when 'purchase' then v_whs.payable_account_id else v_whs.receivable_account_id end;
      select g.account_no, g.name into account_no, account_name from erp.gl_accounts g
      where g.id = case v_type when 'purchase' then v_whs.payable_account_id else v_whs.receivable_account_id end;
      debit  := case when (v_type = 'purchase') = (v_wh_amt > 0) then 0 else abs(v_wh_amt) end;
      credit := case when (v_type = 'purchase') = (v_wh_amt > 0) then abs(v_wh_amt) else 0 end;
      tax_code := v_wh_code; tax_base := v_base_total; line_role := 'withholding';
      src_line := null; amount := null; sign := null; description := null;
      return next;
    end if;
  end if;

  -- 4) Tercero: lado contrario, por el total menos la retención (lo que realmente se paga o se cobra)
  if v_total = 0 then
    raise exception 'The invoice total is zero';
  end if;
  if v_kind = 'invoice' and v_total < 0 then
    raise exception 'The invoice total is negative: register it as a credit memo';
  end if;
  v_n := v_n + 1;
  line_no := v_n; gl_account_id := v_pacc.id; account_no := v_pacc.account_no; account_name := v_pacc.name;
  debit  := case when (v_type = 'purchase') = (v_total - v_wh_amt > 0) then 0 else abs(v_total - v_wh_amt) end;
  credit := case when (v_type = 'purchase') = (v_total - v_wh_amt > 0) then abs(v_total - v_wh_amt) else 0 end;
  tax_code := null; tax_base := null; line_role := 'partner';
  src_line := null; amount := null; sign := null; description := null;
  return next;
end $function$
;

-- 6) Asistente de cierre (versión de la 0048 con el paso de Financiación)
CREATE OR REPLACE FUNCTION erp.closing_checklist(p_company uuid, p_year integer)
 RETURNS TABLE(step integer, code text, status text, detail jsonb, screen text)
 LANGUAGE plpgsql
 STABLE
AS $function$
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
  -- v0.37.0 (0048): con cuentas de existencias, falta; sin ellas pero con compras de aprovisionamientos, revisar
  select count(*) into v_m from erp.gl_accounts g where g.company_id = p_company and g.account_type = 'posting' and g.account_no ~ '^3[0-6]';
  step := 8; code := 'inventory'; screen := 'adjustments';
  status := case when v_n > 0 then 'done' when v_m > 0 then 'pending'
                 when exists (select 1 from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id
                              join erp.gl_accounts g on g.id = l.gl_account_id
                              where e.fiscal_year_id = v_fy.id and e.status = 'posted' and g.account_no ~ '^60[0-2]') then 'review'
                 else 'na' end;
  detail := jsonb_build_object('posted', v_n > 0); return next;

  -- 9) v0.43.0 · Financiación: intereses devengados y reclasificación a corto de los préstamos vivos (y ninguna cuota
  --    vencida sin contabilizar)
  select count(*) into v_m from erp.loans l where l.company_id = p_company and l.status = 'active' and l.start_date <= v_fy.ending_date;
  step := 9; code := 'financing'; screen := 'financing';
  if v_m = 0 then
    status := 'na'; detail := jsonb_build_object('loans', 0);
  else
    declare pv jsonb := erp.loan_year_end_preview(p_company, v_fy.ending_date);
    begin
      status := case when (pv->>'overdue')::int > 0 or (pv->>'accrual_total')::numeric <> 0 or (pv->>'reclassification_total')::numeric <> 0
                     then 'pending' else 'done' end;
      detail := jsonb_build_object('loans', v_m, 'accrual', pv->'accrual_total', 'reclassification', pv->'reclassification_total', 'overdue', pv->'overdue');
    end;
  end if;
  return next;

  -- 10) Comprobaciones del auditor sin avisos ni errores
  select count(*), string_agg(c.code, ', ' order by c.sort) into v_n, v_txt
  from erp.run_audit_checks(p_company, p_year, v_fy.ending_date) c where c.status in ('warning', 'error');
  step := 10; code := 'audit_checks'; screen := 'checks';
  status := case when v_n = 0 then 'done' else 'pending' end; detail := jsonb_build_object('open', v_n, 'codes', v_txt); return next;

  -- 11) v0.41.0 · Impuesto sobre Sociedades (antes de la regularización)
  step := 11; code := 'corporate_tax'; screen := 'corporate_tax';
  status := case when exists (select 1 from erp.corporate_tax_returns r where r.fiscal_year_id = v_fy.id and r.status = 'posted') then 'done'
                 when erp.pre_tax_result(p_company, v_fy.id) = 0 then 'na' else 'pending' end;
  detail := jsonb_build_object('pre_tax_result', erp.pre_tax_result(p_company, v_fy.id)); return next;

  -- 12) Cierre del ejercicio (regularización, cierre y apertura)
  step := 12; code := 'close'; screen := 'closing';
  status := case when v_fy.status = 'closed' then 'done' else 'pending' end;
  detail := jsonb_build_object('fiscal_year_status', v_fy.status); return next;
end $function$
;

-- 7) Comprobaciones del auditor (versión de la 0061 con «financing_ledger»)
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
      -- v0.38.0: más el IRPF de las nóminas (también va al modelo 111, casillas 01 a 03)
      v_book := v_book + coalesce((select sum(s.irpf) from erp.payslips s
                                   join erp.payroll_runs pr on pr.id = s.run_id
                                   join erp.journal_entries je on je.id = pr.entry_id
                                   join erp.fiscal_years f on f.id = je.fiscal_year_id
                                   where pr.company_id = p_company and pr.status = 'posted' and f.year = p_year and pr.period <= v_to), 0);
      -- Contabilidad: asientos que ABONAN la 4751 (las retenciones). Los que la cargan son el ingreso en Hacienda.
      -- Un contraasiento va con su original (por eso se agrupa por k y el signo es el del original).
      with g as (
        select a.k, a.source, min(a.account_no) as account_no, sum(a.credit - a.debit) as amount,
               (select sum(l.credit - l.debit) from erp.journal_lines l join erp.gl_accounts ga on ga.id = l.gl_account_id
                where l.entry_id = a.k and ga.account_no like '4751%' and ga.account_no not like '47512%') as original
        from erp.audit_lines(p_company, p_year, v_to) a
        where a.account_no like '4751%' and a.account_no not like '47512%'   -- v0.42.0: la 47512 (dividendos) va al modelo 123
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

    elsif r.code = 'tax_forms_settlements' then
      -- v0.39.0 · el resultado de cada modelo trimestral (303 / 420, desde el libro registro) frente a su liquidación
      --   contabilizada (desde la contabilidad): un trimestre liquidado aceptando una diferencia
      with q as (
        select g.q, erp.quarter_end(p_year, g.q) as q_end,
               (select b.amount from erp.tax_form_boxes(p_company, p_year, g.q) b where b.box = case v_type when 'VAT' then '46' else '41' end) as form_result,
               (select s.output_tax - s.input_tax from erp.tax_settlements s where s.company_id = p_company and s.tax_type = v_type
                  and s.year = p_year and s.quarter = g.q and s.status = 'posted') as settled
        from generate_series(1, 4) g(q)
        where erp.quarter_end(p_year, g.q) <= v_to
      ), n as (   -- solo los trimestres liquidados (los que faltan por liquidar los avisa el asistente de cierre)
        select q.*, row_number() over (order by q.q) as rn from q
        where q.settled is not null and q.settled <> q.form_result
      )
      select (select coalesce(sum(form_result), 0) from q where settled is not null), (select coalesce(sum(settled), 0) from q), count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('quarter', n.q, 'form', case v_type when 'VAT' then '303' else '420' end,
                                                   'form_result', n.form_result, 'settled', n.settled, 'amount', coalesce(n.settled, 0) - n.form_result)
                                order by n.rn), '[]')
      into v_book, v_ledger, v_items, v_det
      from n;

    elsif r.code = 'form347_missing_vat' then
      -- v0.39.0 · terceros que hay que declarar en el 347 (más de 3.005,06 € en el año) y no tienen NIF
      with n as (select f.*, row_number() over (order by f.partner_name) as rn from erp.form_347(p_company, p_year) f where f.missing_vat_no)
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('partner_id', n.partner_id, 'partner_name', n.partner_name, 'op_key', n.op_key,
                                                   'amount', n.total) order by n.rn) filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'sources_review' then
      -- v0.39.0 · fuentes oficiales sin revisar en más de un año (las normas y las instrucciones cambian)
      with n as (select s.*, row_number() over (order by s.checked, s.key) as rn from erp.sources s where s.checked < current_date - interval '1 year')
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('key', n.key, 'name', n.title, 'issuer', n.issuer, 'checked', n.checked) order by n.rn), '[]')
      into v_items, v_det
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

    elsif r.code in ('provisions_ledger', 'inventory_ledger', 'payroll_ledger', 'financing_ledger') then
      -- v0.37.0 · las cuentas de provisiones (141 / 142 / 5292 / 5293 / 499) y de existencias (30-36 / 39) frente a lo
      --   que han contabilizado sus módulos: la diferencia es un asiento manual o un saldo importado sin su ficha
      with lm as (
        select g.id as acc, sum(jl.debit - jl.credit) as amount,
               bool_or(exists (select 1 from erp.provision_movements pm where pm.entry_id = e.id)
                       or exists (select 1 from erp.inventory_counts ic where ic.entry_id = e.id and ic.status = 'posted')
                       -- v0.38.0: la nómina y sus pagos
                       or exists (select 1 from erp.payroll_runs pr where e.id in (pr.entry_id, pr.net_payment_entry_id, pr.ss_payment_entry_id))
                       -- v0.43.0: los préstamos y el leasing (también la factura de la cuota)
                       or exists (select 1 from erp.loan_events le where le.entry_id = e.id and le.status = 'posted')) as module
        from erp.journal_lines jl join erp.journal_entries e on e.id = jl.entry_id
        join erp.gl_accounts g on g.id = jl.gl_account_id
        where e.company_id = p_company and e.status = 'posted' and e.posting_date <= v_to and e.entry_type <> 'closing'
          and not exists (select 1 from erp.year_closings yc where yc.opening_entry_id = e.id)
          and case r.code when 'provisions_ledger' then g.account_no ~ '^(141|142|5292|5293|499)'
                          when 'payroll_ledger' then g.account_no ~ '^(465|476)'   -- v0.38.0
                          when 'financing_ledger' then g.account_no ~ '^(170|171|174|520|521|524|527|528)'   -- v0.43.0
                          else g.account_no ~ '^3[0-6]|^39' end
          -- un movimiento anulado y su contraasiento se compensan: ninguno de los dos cuenta como del módulo
          and not (e.reversal_of is not null or e.reversed_by is not null)
        group by g.id, e.id
      ), x as (
        select acc, coalesce(sum(amount) filter (where module), 0) as book, sum(amount) as ledger from lm group by acc
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

    elsif r.code = 'provisions_review' then
      -- v0.37.0 · al cierre, provisiones vivas sin revisar en el ejercicio (NRV 15.ª: se revisan en cada cierre)
      with fy as (select f.starting_date, f.ending_date from erp.fiscal_years f where f.company_id = p_company and f.year = p_year),
      n as (
        select pv.id, pv.code, pv.description, erp.provision_balance(pv.id) as balance,
               (select max(m.movement_date) from erp.provision_movements m where m.provision_id = pv.id) as last_date,
               row_number() over (order by pv.code) as rn
        from erp.provisions pv cross join fy
        where pv.company_id = p_company and pv.status = 'active' and v_to >= fy.ending_date
          and exists (select 1 from erp.provision_movements m where m.provision_id = pv.id and m.movement_date < fy.starting_date)
          and not exists (select 1 from erp.provision_movements m where m.provision_id = pv.id
                          and m.movement_date between fy.starting_date and fy.ending_date)
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('provision_id', n.id, 'code', n.code, 'name', n.description,
                                                   'amount', n.balance, 'last_date', n.last_date) order by n.rn)
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

-- 8) Conceptos (generados desde frontend/src/glossary.js con frontend/tests/glossarySql.js)
insert into erp.concepts (key, sort, term, definition, example, term_en, definition_en, example_en, bc, sap, pgc) values
('amortizedCost', 630, 'Coste amortizado', 'Cómo se valora una deuda a lo largo de su vida (NRV 9.ª): lo recibido, más los intereses calculados con el tipo de interés efectivo, menos lo pagado. Así las comisiones y gastos iniciales se reparten como intereses durante el préstamo, en vez de ir a gasto el primer día.', 'Préstamo de 100.000 con 1.000 de comisión: se reciben 99.000 (572 D 99.000); el primer año, intereses de 6.306,83 al 6,3705 %.', 'Amortised cost', 'How a debt is measured over its life (NRV 9): the amount received, plus interest at the effective interest rate, less what has been paid. So upfront fees and costs are spread as interest over the loan instead of being expensed on day one.', 'Loan of 100,000 with a 1,000 fee: 99,000 is received (572 Dr 99,000); first-year interest is 6,306.83 at 6.3705 %.', 'Not standard: loans by general journal or extensions', 'Effective interest method (Treasury and Risk Management)', '{170,520,662}'),
('effectiveRate', 640, 'Tipo de interés efectivo (TIE)', 'El tipo que iguala lo que se recibe con todos los pagos futuros, como la TIR de una hoja de cálculo. Incluye las comisiones y gastos, por eso es mayor que el nominal si los hay. Con él se calculan los intereses de cada periodo a coste amortizado.', '99.000 recibidos y 5 cuotas de 23.739,64 → TIE del 6,3705 % (el nominal es el 6 %).', 'Effective interest rate (EIR)', 'The rate that equals the amount received with all future payments, like the IRR of a spreadsheet. It includes fees and costs, so it is higher than the nominal rate if there are any. It is used to calculate each period''s interest at amortised cost.', '99,000 received and 5 instalments of 23,739.64 → EIR of 6.3705 % (the nominal rate is 6 %).', 'Not calculated as standard', 'Effective interest rate', '{662}'),
('financeLease', 650, 'Arrendamiento financiero (leasing)', 'Un alquiler que transfiere los riesgos y beneficios del bien, por ejemplo con una opción de compra que seguro se ejercerá (NRV 8.ª). El arrendatario registra el activo y la deuda por el menor del valor razonable y el valor actual de los pagos. Cada cuota lleva principal, intereses e IVA / IGIC.', 'Máquina de 50.000: 213 D 50.000 / 5240 H 11.030,59 · 1740 H 38.969,41; primera cuota: 5240 D 11.030,59 · 6623 D 2.469,41 · 472 D 945 / 410 H 14.445.', 'Finance lease', 'A lease that transfers the risks and rewards of the asset, for example with a purchase option that will certainly be exercised (NRV 8). The lessee records the asset and the debt at the lower of fair value and the present value of the payments. Each instalment has principal, interest and VAT / IGIC.', 'Machine of 50,000: 213 Dr 50,000 / 5240 Cr 11,030.59 · 1740 Cr 38,969.41; first instalment: 5240 Dr 11,030.59 · 6623 Dr 2,469.41 · 472 Dr 945 / 410 Cr 14,445.', 'Not standard: lease extensions', 'Lease accounting (RE-FX / Lease Administration)', '{174,524,213}'),
('debtMaturity', 660, 'Deuda a corto y a largo plazo', 'En el balance, una deuda se divide según cuándo se paga: lo que vence en los 12 meses siguientes va a corto (520, 524) y el resto, a largo (170, 174). Al cierre, lo que vence el año siguiente pasa del largo al corto (reclasificación).', 'Al 31/12/2026 quedan 82.260,36 y en 2027 se pagarán 18.804,02 → 1700 D 18.804,02 / 5200 H 18.804,02.', 'Current and non-current debt', 'In the balance sheet a debt is split by when it is paid: what falls due in the next 12 months is current (520, 524) and the rest non-current (170, 174). At year end, what falls due next year moves from non-current to current (reclassification).', 'At 31/12/2026, 82,260.36 is outstanding and 18,804.02 will be paid in 2027 → 1700 Dr 18,804.02 / 5200 Cr 18,804.02.', 'Not automatic: reclassified by journal', 'Regrouping of payables by remaining term (F101)', '{170,520,174,524}')
on conflict (key) do update set
  sort = excluded.sort, term = excluded.term, definition = excluded.definition, example = excluded.example,
  term_en = excluded.term_en, definition_en = excluded.definition_en, example_en = excluded.example_en,
  bc = excluded.bc, sap = excluded.sap, pgc = excluded.pgc;

-- 9) Cuentas controladas
insert into erp.control_rules (account_prefix, modules, side, note, note_en) values
('170', '{financing}', 'both', 'Deudas a largo plazo con entidades de crédito: las mueven el alta del préstamo, sus cuotas y la reclasificación del cierre.', 'Long-term bank debt: posted by the loan, its instalments and the year-end reclassification.'),
('171', '{financing}', 'both', 'Otras deudas a largo plazo: las mueven el alta del préstamo, sus cuotas y la reclasificación del cierre.', 'Other long-term debt: posted by the loan, its instalments and the year-end reclassification.'),
('174', '{financing}', 'both', 'Acreedores por arrendamiento financiero a largo plazo: los mueven el alta del leasing y la reclasificación del cierre.', 'Long-term finance lease payables: posted by the lease and the year-end reclassification.'),
('520', '{financing}', 'both', 'Deudas a corto plazo con entidades de crédito: las mueven el préstamo, sus cuotas y la reclasificación del cierre.', 'Short-term bank debt: posted by the loan, its instalments and the year-end reclassification.'),
('521', '{financing}', 'both', 'Otras deudas a corto plazo: las mueven el préstamo, sus cuotas y la reclasificación del cierre.', 'Other short-term debt: posted by the loan, its instalments and the year-end reclassification.'),
('524', '{financing,invoices}', 'both', 'Acreedores por arrendamiento financiero a corto plazo: los mueven el alta del leasing, la reclasificación y la factura de cada cuota (desde Financiación).', 'Short-term finance lease payables: posted by the lease, the reclassification and each instalment invoice (from Financing).'),
('527', '{financing}', 'both', 'Intereses devengados de deudas con entidades de crédito: los mueven el cierre (devengo) y la cuota que los paga.', 'Accrued interest on bank debt: posted at year end (accrual) and by the instalment that pays it.'),
('528', '{financing}', 'both', 'Intereses devengados de otras deudas: los mueven el cierre (devengo) y la cuota que los paga.', 'Accrued interest on other debt: posted at year end (accrual) and by the instalment that pays it.')
on conflict (account_prefix) do update set modules = excluded.modules, side = excluded.side, note = excluded.note, note_en = excluded.note_en;

-- 10) Comprobación nueva del auditor
insert into erp.audit_checks (code, sort, area, severity, title, title_en, why, why_en, fix, fix_en, screen, concept) values
('financing_ledger', 64, 'ledger', 'warning',
 'Préstamos y leasing frente a la contabilidad',
 'Loans and leases against the books',
 'La 170, 171, 174, 520, 521, 524, 527 y 528 solo deben moverse desde Financiación: así cada saldo tiene su cuadro de amortización, se reclasifica al cierre y sus intereses se calculan con el tipo de interés efectivo. Un asiento manual o un saldo importado sin préstamo queda sin control.',
 'Accounts 170, 171, 174, 520, 521, 524, 527 and 528 should only be posted from Financing: so each balance has its amortisation schedule, is reclassified at year end and its interest follows the effective interest rate. A manual entry or an imported balance without a loan is out of control.',
 'Da de alta el préstamo o el leasing en Financiación (y anula el asiento manual), o revierte el saldo importado que ya no corresponde.',
 'Create the loan or lease in Financing (and reverse the manual entry), or reverse the imported balance.',
 'financing', 'amortizedCost')
on conflict (code) do update set sort = excluded.sort, area = excluded.area, severity = excluded.severity,
  title = excluded.title, title_en = excluded.title_en, why = excluded.why, why_en = excluded.why_en,
  fix = excluded.fix, fix_en = excluded.fix_en, screen = excluded.screen, concept = excluded.concept;

-- 11) Catálogo de operaciones y supuestos
insert into erp.operations (key, sort, title, title_en, screen, entry, entry_en, accounts, concept, sources, description, description_en) values
('loan', 187, 'Préstamo bancario a coste amortizado', 'Bank loan at amortised cost', 'financing',
 '572 D / 5200 H · 1700 H; cuota: 6623 D + 5200 D / 572 H; cierre: 1700 D / 5200 H', '572 Dr / 5200 Cr · 1700 Cr; instalment: 6623 Dr + 5200 Dr / 572 Cr; year end: 1700 Dr / 5200 Cr',
 '{170,520,662}', 'amortizedCost', '{pgc}',
 'El cobro por lo recibido (sin las comisiones), dividido entre corto y largo; cada cuota, con los intereses al tipo efectivo; al cierre, los intereses devengados y la reclasificación a corto.',
 'The amount received (net of fees), split into current and non-current; each instalment, with interest at the effective rate; at year end, accrued interest and the reclassification to current.'),
('finance_lease', 188, 'Arrendamiento financiero (leasing)', 'Finance lease', 'financing',
 '213 D / 5240 H · 1740 H; cuota (factura): 5240 D + 6623 D + 472 D / 410 H', '213 Dr / 5240 Cr · 1740 Cr; instalment (invoice): 5240 Dr + 6623 Dr + 472 Dr / 410 Cr',
 '{213,174,524}', 'financeLease', '{pgc}',
 'El activo y la deuda por el menor del valor razonable y el valor actual de los pagos; cada cuota llega como factura de la entidad, con su principal, sus intereses y su IVA / IGIC; el activo se amortiza en Inmovilizado.',
 'The asset and the debt at the lower of fair value and present value of the payments; each instalment is an invoice from the lessor with principal, interest and VAT / IGIC; the asset is depreciated in Fixed assets.')
on conflict (key) do update set sort = excluded.sort, title = excluded.title, title_en = excluded.title_en, screen = excluded.screen,
  entry = excluded.entry, entry_en = excluded.entry_en, accounts = excluded.accounts, concept = excluded.concept,
  sources = excluded.sources, description = excluded.description, description_en = excluded.description_en;

insert into erp.exercises (key, sort, level, operation, tax_type, title, title_en, statement, statement_en, expected, explanation, explanation_en, errors, sources, concept) values
('loan_with_fee', 190, 'advanced', 'loan', null, 'Préstamo con comisión de apertura', 'Loan with an opening fee',
 'El 01/01 el banco te ingresa un préstamo de 100.000 € al 6 % en 5 cuotas anuales de 23.739,64 €, la primera el 31/12. Te cobra una comisión de apertura de 1.000 €, que descuenta del ingreso. La deuda baja 17.432,81 € con la primera cuota, calculada al tipo de interés efectivo. Contabiliza el cobro.',
 'On 01/01 the bank pays you a loan of €100,000 at 6 % in 5 annual instalments of €23,739.64, the first on 31/12. It charges a €1,000 opening fee, deducted from the amount paid. The debt goes down by €17,432.81 with the first instalment, at the effective interest rate. Record the receipt.',
 '[{"account": "572", "side": "debit", "amount": 99000}, {"account": "520", "side": "credit", "amount": 17432.81}, {"account": "170", "side": "credit", "amount": 81567.19}]',
 'A coste amortizado (NRV 9.ª) la deuda se registra por lo recibido, 99.000: la comisión no es gasto del primer día, va dentro del tipo de interés efectivo (6,3705 %) y se reparte como intereses durante el préstamo. Lo que se devuelve en los 12 meses siguientes (17.432,81) va a corto (520) y el resto, a largo (170).',
 'At amortised cost (NRV 9) the debt is recorded at the amount received, 99,000: the fee is not an expense on day one, it is part of the effective interest rate (6.3705 %) and is spread as interest over the loan. What is repaid in the next 12 months (17,432.81) is current (520) and the rest non-current (170).',
 '[{"account": "626", "side": "debit", "msg": "La comisión no es gasto del primer día: va dentro del tipo de interés efectivo (NRV 9.ª), por eso la deuda se registra por 99.000.", "msg_en": "The fee is not an expense on day one: it is part of the effective interest rate (NRV 9), so the debt is recorded at 99,000."},
   {"account": "669", "side": "debit", "msg": "La comisión no va a gastos financieros el primer día: se reparte como intereses con el tipo efectivo.", "msg_en": "The fee is not a finance expense on day one: it is spread as interest with the effective rate."},
   {"account": "662", "side": "debit", "msg": "Al cobrar el préstamo aún no hay intereses: se devengan con el tiempo y se pagan con cada cuota.", "msg_en": "There is no interest yet when the loan is received: it accrues over time and is paid with each instalment."}]',
 '{pgc}', 'amortizedCost'),
('leasing_start', 200, 'advanced', 'finance_lease', null, 'Alta de un leasing', 'Start of a finance lease',
 'El 01/01 recibes una máquina en leasing: valor razonable 50.000 €, 4 cuotas anuales de 13.500 € y una opción de compra de 2.500 € con la última, que se va a ejercer. Con el tipo implícito (4,9388 %), la deuda baja 11.030,59 € con la primera cuota. Contabiliza el alta (sin el IVA / IGIC, que va en cada cuota).',
 'On 01/01 you receive a machine under a finance lease: fair value €50,000, 4 annual instalments of €13,500 and a €2,500 purchase option with the last one, which will be exercised. At the implicit rate (4.9388 %) the debt goes down by €11,030.59 with the first instalment. Record the start (without VAT / IGIC, which goes with each instalment).',
 '[{"account": "213", "side": "debit", "amount": 50000}, {"account": "524", "side": "credit", "amount": 11030.59}, {"account": "174", "side": "credit", "amount": 38969.41}]',
 'Con una opción de compra que se va a ejercer, se transfieren los riesgos y beneficios: es arrendamiento financiero (NRV 8.ª). La máquina va al inmovilizado (213) por el menor del valor razonable y el valor actual de los pagos (aquí, 50.000), y la deuda se divide entre lo que se paga en 12 meses (524) y el resto (174).',
 'With a purchase option that will be exercised, the risks and rewards are transferred: it is a finance lease (NRV 8). The machine goes to fixed assets (213) at the lower of fair value and present value of the payments (here 50,000), and the debt is split into what is paid within 12 months (524) and the rest (174).',
 '[{"account": "621", "side": "debit", "msg": "Es arrendamiento financiero, no un alquiler operativo: la máquina se registra como inmovilizado (NRV 8.ª), no como gasto de arrendamiento.", "msg_en": "It is a finance lease, not an operating lease: the machine is recorded as a fixed asset (NRV 8), not as a rental expense."},
   {"account": "472", "side": "debit", "msg": "En el alta no hay IVA / IGIC: el leasing es un servicio y el impuesto va en cada cuota.", "msg_en": "There is no VAT / IGIC at the start: the lease is a service and the tax goes with each instalment."},
   {"account": "173", "side": "credit", "msg": "La deuda del leasing tiene sus cuentas: 174 (largo plazo) y 524 (corto plazo).", "msg_en": "The lease debt has its own accounts: 174 (non-current) and 524 (current)."}]',
 '{pgc}', 'financeLease')
on conflict (key) do update set sort = excluded.sort, level = excluded.level, operation = excluded.operation, tax_type = excluded.tax_type,
  title = excluded.title, title_en = excluded.title_en, statement = excluded.statement, statement_en = excluded.statement_en,
  expected = excluded.expected, explanation = excluded.explanation, explanation_en = excluded.explanation_en,
  errors = excluded.errors, sources = excluded.sources, concept = excluded.concept;
