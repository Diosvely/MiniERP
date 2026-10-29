-- =====================================================================
-- erp.reverse_asset_impairment · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0046_asset_impairment   →   la vigente es la de 0046_asset_impairment
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.reverse_asset_impairment(p jsonb)
 RETURNS TABLE(entry_no integer, amount numeric, net_book_value numeric, capped boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  a       erp.fixed_assets;
  v_date  date := (p->>'reversal_date')::date;
  v_rec   numeric := round((p->>'recoverable_value')::numeric, 2);
  v_nbv   numeric;
  v_max   numeric;
  v_amt   numeric;
  v_no    text;
  v_entry uuid;
  v_n     int;
begin
  select * into a from erp.fixed_assets where id = (p->>'asset_id')::uuid;
  if not found then raise exception 'Asset not found'; end if;
  if not erp.can_write(a.company_id) then raise exception 'No permission to register fixed assets in this company'; end if;
  perform erp.asset_event_check(a, v_date);
  if erp.asset_impairment_at(a.id, v_date) <= 0 then raise exception 'Asset % has no impairment to reverse', a.code; end if;
  if v_rec is null or v_rec < 0 then raise exception 'Give the new recoverable value'; end if;
  v_nbv := erp.asset_net_value_at(a.id, v_date);
  -- valor neto sin deterioro: coste − la amortización del plan original a esa fecha
  v_max := least(erp.asset_impairment_at(a.id, v_date),
                 (erp.asset_cost_at(a.id, v_date) - erp.asset_accumulated_at(erp.asset_cost_at(a.id, v_date), a.residual_value,
                   a.useful_life_months, a.start_date, v_date)) - v_nbv);
  v_amt := least(v_rec - v_nbv, v_max);
  if v_amt <= 0 then raise exception 'No reversal: the recoverable value (%) is not above the net book value (%)', v_rec, v_nbv; end if;
  v_no := (select account_no from erp.gl_accounts where id = a.asset_account_id);
  v_entry := erp.adjust_post(a.company_id, v_date, 'Reversión del deterioro de ' || a.code || ' · ' || a.name, null,
    erp.asset_impairment_account(a.company_id, v_no, 'allowance'), erp.asset_impairment_account(a.company_id, v_no, 'reversal'), v_amt);
  insert into erp.asset_events (asset_id, company_id, kind, event_date, amount, recoverable, entry_id)
  values (a.id, a.company_id, 'reversal', v_date, v_amt, v_rec, v_entry);
  perform set_config('erp.asset_engine', 'on', true);
  v_n := erp.adjust_finish(v_entry);
  perform set_config('erp.asset_engine', 'off', true);
  entry_no := v_n; amount := v_amt; net_book_value := v_nbv + v_amt; capped := v_rec - v_nbv > v_max;
  return next;
end $function$
;
