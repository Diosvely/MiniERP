-- =====================================================================
-- erp.post_payment · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0035_payments   →   la vigente es la de 0035_payments
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.post_payment(p jsonb)
 RETURNS TABLE(payment_id uuid, entry_no integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
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
end $function$
;
