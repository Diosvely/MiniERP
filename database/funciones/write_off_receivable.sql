-- =====================================================================
-- erp.write_off_receivable · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0043_year_end_adjustments   →   la vigente es la de 0043_year_end_adjustments
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.write_off_receivable(p jsonb)
 RETURNS TABLE(writeoff_id uuid, entry_no integer, amount numeric, impairment_applied numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  v_inv     erp.invoices;
  v_date    date := (p->>'writeoff_date')::date;
  v_partner erp.business_partners;
  v_oi      record;
  v_imp     erp.receivable_impairments;
  v_loss    uuid;
  v_entry   uuid;
  v_pay     uuid;
  v_id      uuid;
  v_no      int;
  v_desc    text;
begin
  select * into v_inv from erp.invoices where id = (p->>'invoice_id')::uuid;
  if not found then raise exception 'Invoice not found'; end if;
  if not erp.can_write(v_inv.company_id) then raise exception 'No permission to register impairments in this company'; end if;
  if v_inv.invoice_type <> 'sale' or v_inv.document_kind <> 'invoice' then raise exception 'Only issued invoices can be written off'; end if;
  if v_date is null then raise exception 'The write-off date is required'; end if;
  select * into v_oi from erp.open_items(v_inv.company_id, v_date) o where o.invoice_id = v_inv.id;
  if v_oi is null or v_oi.pending <= 0 then raise exception 'Invoice % has nothing pending at %', v_inv.invoice_no, v_date; end if;
  select * into v_partner from erp.business_partners where id = v_inv.partner_id;
  if v_partner.gl_account_id is null then raise exception 'Partner % has no posting account', v_partner.name; end if;
  select * into v_imp from erp.receivable_impairments i where i.invoice_id = v_inv.id and i.status = 'active';
  if v_imp.id is not null and v_imp.impair_date > v_date then
    raise exception 'The write-off cannot be earlier than the impairment (%)', v_imp.impair_date;
  end if;

  v_desc := coalesce(nullif(btrim(p->>'description'), ''), 'Insolvencia firme · factura ' || v_inv.invoice_no || ' · ' || v_partner.name);
  v_loss := erp.adjust_account(v_inv.company_id, '650', 'Pérdidas de créditos comerciales incobrables');
  v_entry := erp.adjust_post(v_inv.company_id, v_date, v_desc, v_inv.invoice_no, v_loss, v_partner.gl_account_id, v_oi.pending, v_partner.id);
  if v_imp.id is not null then
    insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description) values
      (v_entry, v_inv.company_id, 3, erp.adjust_account(v_inv.company_id, '490', 'Deterioro de valor de créditos por operaciones comerciales'),
       v_imp.amount, 0, 'Aplicación del deterioro ' || v_imp.code),
      (v_entry, v_inv.company_id, 4, erp.adjust_account(v_inv.company_id, '794', 'Reversión del deterioro de créditos por operaciones comerciales'),
       0, v_imp.amount, 'Aplicación del deterioro ' || v_imp.code);
  end if;

  -- La partida abierta se cierra como un cobro (sin banco: la «contrapartida» es la 650)
  insert into erp.payments (company_id, payment_type, partner_id, payment_date, cash_account_id, amount, description, entry_id)
  values (v_inv.company_id, 'collection', v_partner.id, v_date, v_loss, v_oi.pending, v_desc, v_entry)
  returning id into v_pay;
  insert into erp.payment_applications (payment_id, invoice_id, company_id, amount)
  values (v_pay, v_inv.id, v_inv.company_id, v_oi.pending);
  insert into erp.receivable_writeoffs (company_id, invoice_id, partner_id, writeoff_date, amount, impairment_id, impairment_applied, entry_id, payment_id)
  values (v_inv.company_id, v_inv.id, v_partner.id, v_date, v_oi.pending, v_imp.id, coalesce(v_imp.amount, 0), v_entry, v_pay)
  returning id into v_id;
  if v_imp.id is not null then
    update erp.receivable_impairments set status = 'written_off', end_date = v_date, end_entry_id = v_entry where id = v_imp.id;
  end if;
  v_no := erp.adjust_finish(v_entry);
  writeoff_id := v_id; entry_no := v_no; amount := v_oi.pending; impairment_applied := coalesce(v_imp.amount, 0);
  return next;
end $function$
;
