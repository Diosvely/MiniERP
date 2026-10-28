-- =====================================================================
-- erp.tg_invoice_line_asset_cost · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0046_asset_impairment   →   la vigente es la de 0046_asset_impairment
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_invoice_line_asset_cost()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare v_inv erp.invoices; a erp.fixed_assets; v_delta numeric;
begin
  if coalesce(current_setting('erp.deleting_company', true), '') = 'on' then return new; end if;
  select * into v_inv from erp.invoices where id = new.invoice_id;
  if v_inv.document_kind <> 'credit_memo' or v_inv.invoice_type <> 'purchase' or v_inv.corrected_invoice_id is null then return new; end if;
  select * into a from erp.fixed_assets x
  where x.invoice_id = v_inv.corrected_invoice_id and x.asset_account_id = new.gl_account_id
  order by x.code limit 1;
  if not found then return new; end if;
  v_delta := round(new.amount * new.sign, 2);
  if a.status <> 'active' then raise exception 'Asset % is disposed: its purchase can no longer be credited', a.code; end if;
  if exists (select 1 from erp.asset_depreciations d where d.asset_id = a.id and d.period_end > v_inv.posting_date) then
    raise exception 'Asset % is already depreciated after %: cancel that depreciation first', a.code, v_inv.posting_date;
  end if;
  if exists (select 1 from erp.asset_events x where x.asset_id = a.id and x.event_date > v_inv.posting_date) then
    raise exception 'Asset % has a later impairment or adjustment', a.code;
  end if;
  if a.cost + v_delta <= a.residual_value then
    raise exception 'The credit memo leaves asset % without depreciable cost: retire it in Fixed assets instead', a.code;
  end if;
  insert into erp.asset_events (asset_id, company_id, kind, event_date, amount, invoice_id)
  values (a.id, a.company_id, 'cost_adjustment', v_inv.posting_date, v_delta, v_inv.id);
  update erp.fixed_assets set cost = cost + v_delta where id = a.id;
  return new;
end $function$
;
