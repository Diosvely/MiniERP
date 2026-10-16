-- =====================================================================
-- erp.dispose_asset · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0041_fixed_assets   →   la vigente es la de 0041_fixed_assets
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.dispose_asset(p jsonb)
 RETURNS TABLE(entry_no integer, net_book_value numeric, result numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare
  a        erp.fixed_assets;
  v_date   date := (p->>'disposal_date')::date;
  v_inv    erp.invoices;
  v_price  numeric := 0;
  v_fy     uuid;
  v_entry  uuid;
  v_catch  numeric;
  v_acc    numeric;
  v_nbv    numeric;
  v_res    numeric;
  v_digits int;
  v_no     int;
  v_line   int := 0;
begin
  select * into a from erp.fixed_assets where id = (p->>'asset_id')::uuid;
  if not found then raise exception 'Asset not found'; end if;
  if not erp.can_write(a.company_id) then raise exception 'No permission to register fixed assets in this company'; end if;
  if a.status <> 'active' then raise exception 'Asset % is already disposed', a.code; end if;
  if v_date is null then raise exception 'The disposal date is required'; end if;
  if v_date < a.start_date then raise exception 'The disposal date cannot be earlier than the start date'; end if;
  if exists (select 1 from erp.asset_depreciations d where d.asset_id = a.id and d.period_end > v_date) then
    raise exception 'Asset % is already depreciated after %: cancel that depreciation first', a.code, v_date;
  end if;
  select id into v_fy from erp.fiscal_years where company_id = a.company_id and v_date between starting_date and ending_date;
  if v_fy is null then raise exception 'No fiscal year for date %', v_date; end if;

  -- Factura de venta: emitida, de esta empresa, y con su línea en la cuenta del activo (eso es el precio)
  if p->>'invoice_id' is not null then
    select * into v_inv from erp.invoices i where i.id = (p->>'invoice_id')::uuid and i.company_id = a.company_id;
    if not found or v_inv.invoice_type <> 'sale' then raise exception 'The sale must be an issued invoice of this company'; end if;
    select coalesce(sum(l.amount * l.sign), 0) into v_price from erp.invoice_lines l
    where l.invoice_id = v_inv.id and l.gl_account_id = a.asset_account_id;
    if v_price <= 0 then raise exception 'Invoice % has no line on the asset account', v_inv.invoice_no; end if;
    if exists (select 1 from erp.fixed_assets x where x.disposal_invoice_id = v_inv.id) then
      raise exception 'Invoice % is already used for another disposal', v_inv.invoice_no;
    end if;
  end if;

  v_catch := erp.asset_accumulated_at(a.cost, a.residual_value, a.useful_life_months, a.start_date, v_date) - erp.asset_posted(a.id);
  v_acc := erp.asset_posted(a.id) + greatest(v_catch, 0);
  v_nbv := a.cost - v_acc;
  v_res := v_price - v_nbv;
  v_digits := (select posting_account_digits from erp.companies where id = a.company_id);

  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no)
  values (a.company_id, v_fy, v_date, left(case when v_inv.id is null then 'Baja de ' else 'Venta de ' end || a.code || ' · ' || a.name, 250),
          v_inv.invoice_no)
  returning id into v_entry;
  if v_catch > 0 then
    insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description) values
      (v_entry, a.company_id, 1, a.expense_account_id, v_catch, 0, 'Amortización hasta la baja'),
      (v_entry, a.company_id, 2, a.depreciation_account_id, 0, v_catch, 'Amortización hasta la baja');
    v_line := 2;
    insert into erp.asset_depreciations (asset_id, company_id, period_end, amount, entry_id)
    values (a.id, a.company_id, v_date, v_catch, v_entry);
  end if;
  if v_acc > 0 then
    insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description)
    values (v_entry, a.company_id, v_line + 1, a.depreciation_account_id, v_acc, 0, 'Cancelación de la amortización acumulada');
    v_line := v_line + 1;
  end if;
  if a.cost - v_price <> 0 then
    insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description)
    values (v_entry, a.company_id, v_line + 1, a.asset_account_id,
            greatest(v_price - a.cost, 0), greatest(a.cost - v_price, 0), 'Baja del activo');
    v_line := v_line + 1;
  end if;
  if v_res <> 0 then
    insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description)
    values (v_entry, a.company_id, v_line + 1,
            erp.asset_result_account(a.company_id, (select account_no from erp.gl_accounts where id = a.asset_account_id), v_res),
            greatest(-v_res, 0), greatest(v_res, 0), case when v_res < 0 then 'Pérdida' else 'Beneficio' end || ' en la baja');
  end if;
  perform set_config('erp.asset_engine', 'on', true);
  v_no := erp.post_entry(v_entry);
  perform set_config('erp.asset_engine', 'off', true);

  update erp.fixed_assets set status = 'disposed', disposal_date = v_date, disposal_price = v_price,
                              disposal_invoice_id = v_inv.id, disposal_entry_id = v_entry
  where id = a.id;
  entry_no := v_no; net_book_value := v_nbv; result := v_res;
  return next;
end $function$
;
