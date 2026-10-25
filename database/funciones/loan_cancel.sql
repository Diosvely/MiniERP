-- =====================================================================
-- erp.loan_cancel · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0062_loans 0063_financing_integration   →   la vigente es la de 0063_financing_integration
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.loan_cancel(p_loan uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
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
end $function$
;
