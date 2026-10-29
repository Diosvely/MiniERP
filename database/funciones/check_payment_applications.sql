-- =====================================================================
-- erp.check_payment_applications · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0035_payments   →   la vigente es la de 0035_payments
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.check_payment_applications(p_company uuid, p_partner uuid, p_type text, p_apps jsonb)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
 SET jit TO 'off'
AS $function$
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
end $function$
;
