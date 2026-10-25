-- =====================================================================
-- erp.loan_instalment_invoice · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0063_financing_integration   →   la vigente es la de 0063_financing_integration
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.loan_instalment_invoice(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
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
end $function$
;
