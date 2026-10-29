-- =====================================================================
-- erp.impair_receivable · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0043_year_end_adjustments   →   la vigente es la de 0043_year_end_adjustments
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.impair_receivable(p jsonb)
 RETURNS TABLE(impairment_id uuid, code text, entry_no integer, amount numeric, warnings jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  v_inv   erp.invoices;
  v_date  date := (p->>'impair_date')::date;
  v_pct   numeric := coalesce((p->>'pct')::numeric, 100);
  v_oi    record;
  v_amt   numeric;
  v_warn  jsonb := '[]';
  v_code  text;
  v_entry uuid;
  v_id    uuid;
  v_no    int;
begin
  select * into v_inv from erp.invoices where id = (p->>'invoice_id')::uuid;
  if not found then raise exception 'Invoice not found'; end if;
  if not erp.can_write(v_inv.company_id) then raise exception 'No permission to register impairments in this company'; end if;
  if v_inv.invoice_type <> 'sale' or v_inv.document_kind <> 'invoice' then
    raise exception 'Only issued invoices (customer receivables) can be impaired';
  end if;
  if v_date is null then raise exception 'The impairment date is required'; end if;
  if v_pct <= 0 or v_pct > 100 then raise exception 'The percentage must be between 0 and 100'; end if;
  if exists (select 1 from erp.receivable_impairments i where i.invoice_id = v_inv.id and i.status = 'active') then
    raise exception 'Invoice % is already impaired: reverse that impairment first', v_inv.invoice_no;
  end if;
  select * into v_oi from erp.open_items(v_inv.company_id, v_date) o where o.invoice_id = v_inv.id;
  if v_oi is null or v_oi.pending <= 0 then raise exception 'Invoice % has nothing pending at %', v_inv.invoice_no, v_date; end if;
  v_amt := round(v_oi.pending * v_pct / 100, 2);

  -- LIS art. 13.1.a: deducible cuando han pasado 6 meses desde el vencimiento
  if v_date < (v_oi.due_date + interval '6 months')::date then
    v_warn := v_warn || jsonb_build_object('code', 'not_deductible_6m', 'due_date', v_oi.due_date,
                                           'deductible_from', (v_oi.due_date + interval '6 months')::date);
  end if;

  select 'DET-' || lpad((count(*) + 1)::text, 4, '0') into v_code from erp.receivable_impairments i where i.company_id = v_inv.company_id;
  v_entry := erp.adjust_post(v_inv.company_id, v_date,
    'Deterioro ' || v_code || ' · factura ' || v_inv.invoice_no || ' · ' || v_oi.partner_name, v_inv.invoice_no,
    erp.adjust_account(v_inv.company_id, '694', 'Pérdidas por deterioro de créditos por operaciones comerciales'),
    erp.adjust_account(v_inv.company_id, '490', 'Deterioro de valor de créditos por operaciones comerciales'), v_amt);
  insert into erp.receivable_impairments (company_id, code, method, invoice_id, partner_id, impair_date, basis, pct, amount, warnings, entry_id)
  values (v_inv.company_id, v_code, 'individual', v_inv.id, v_inv.partner_id, v_date, v_oi.pending, v_pct, v_amt, v_warn, v_entry)
  returning id into v_id;
  v_no := erp.adjust_finish(v_entry);
  impairment_id := v_id; code := v_code; entry_no := v_no; amount := v_amt; warnings := v_warn;
  return next;
end $function$
;
