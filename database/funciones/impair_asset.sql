-- =====================================================================
-- erp.impair_asset · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0046_asset_impairment   →   la vigente es la de 0046_asset_impairment
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.impair_asset(p jsonb)
 RETURNS TABLE(entry_no integer, amount numeric, net_book_value numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare
  a       erp.fixed_assets;
  v_date  date := (p->>'impairment_date')::date;
  v_nbv   numeric;
  v_rec   numeric := round((p->>'recoverable_value')::numeric, 2);
  v_amt   numeric := round((p->>'amount')::numeric, 2);
  v_no    text;
  v_entry uuid;
  v_n     int;
begin
  select * into a from erp.fixed_assets where id = (p->>'asset_id')::uuid;
  if not found then raise exception 'Asset not found'; end if;
  if not erp.can_write(a.company_id) then raise exception 'No permission to register fixed assets in this company'; end if;
  perform erp.asset_event_check(a, v_date);
  v_nbv := erp.asset_net_value_at(a.id, v_date);
  if v_rec is not null then
    if v_rec < 0 then raise exception 'The recoverable value cannot be negative'; end if;
    v_amt := v_nbv - v_rec;
    if v_amt <= 0 then raise exception 'No impairment: the recoverable value (%) is not below the net book value (%)', v_rec, v_nbv; end if;
  end if;
  if v_amt is null or v_amt <= 0 then raise exception 'Give the recoverable value (or the impairment amount)'; end if;
  if v_amt > v_nbv then raise exception 'The impairment (%) cannot exceed the net book value (%)', v_amt, v_nbv; end if;
  v_no := (select account_no from erp.gl_accounts where id = a.asset_account_id);
  v_entry := erp.adjust_post(a.company_id, v_date, 'Deterioro de ' || a.code || ' · ' || a.name, null,
    erp.asset_impairment_account(a.company_id, v_no, 'expense'), erp.asset_impairment_account(a.company_id, v_no, 'allowance'), v_amt);
  insert into erp.asset_events (asset_id, company_id, kind, event_date, amount, recoverable, entry_id)
  values (a.id, a.company_id, 'impairment', v_date, v_amt, v_rec, v_entry);
  perform set_config('erp.asset_engine', 'on', true);
  v_n := erp.adjust_finish(v_entry);
  perform set_config('erp.asset_engine', 'off', true);
  entry_no := v_n; amount := v_amt; net_book_value := v_nbv - v_amt;
  return next;
end $function$
;
