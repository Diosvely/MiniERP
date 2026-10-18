-- =====================================================================
-- erp.cancel_asset_impairment · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0046_asset_impairment   →   la vigente es la de 0046_asset_impairment
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.cancel_asset_impairment(p_asset uuid, p_date date DEFAULT NULL::date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare a erp.fixed_assets; ev erp.asset_events; v_n int;
begin
  select * into a from erp.fixed_assets where id = p_asset;
  if not found then raise exception 'Asset not found'; end if;
  if not erp.can_write(a.company_id) then raise exception 'No permission to register fixed assets in this company'; end if;
  if a.status <> 'active' then raise exception 'Asset % is already disposed', a.code; end if;
  select * into ev from erp.asset_events x where x.asset_id = a.id order by x.event_date desc, x.created_at desc limit 1;
  if ev.id is null or ev.kind = 'cost_adjustment' then raise exception 'Asset % has no impairment to undo', a.code; end if;
  if exists (select 1 from erp.asset_depreciations d where d.asset_id = a.id and d.period_end > ev.event_date) then
    raise exception 'Asset % is already depreciated after %: cancel that depreciation first', a.code, ev.event_date;
  end if;
  perform set_config('erp.asset_engine', 'on', true);
  v_n := erp.adjust_reverse(ev.entry_id, coalesce(p_date, ev.event_date), 'Deterioro deshecho');
  perform set_config('erp.asset_engine', 'off', true);
  delete from erp.asset_events where id = ev.id;
  return v_n;
end $function$
;
