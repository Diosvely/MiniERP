-- =====================================================================
-- erp.asset_event_check · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0046_asset_impairment   →   la vigente es la de 0046_asset_impairment
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.asset_event_check(a erp.fixed_assets, p_date date)
 RETURNS void
 LANGUAGE plpgsql
 STABLE
AS $function$
begin
  if a.status <> 'active' then raise exception 'Asset % is already disposed', a.code; end if;
  if p_date is null then raise exception 'The date is required'; end if;
  if p_date < a.start_date then raise exception 'The date cannot be earlier than the start date'; end if;
  if exists (select 1 from erp.asset_depreciations d where d.asset_id = a.id and d.period_end > p_date) then
    raise exception 'Asset % is already depreciated after %: cancel that depreciation first', a.code, p_date;
  end if;
  if exists (select 1 from erp.asset_events x where x.asset_id = a.id and x.event_date > p_date) then
    raise exception 'Asset % has a later impairment or adjustment', a.code;
  end if;
  if erp.asset_depr_at(a.id, p_date) - erp.asset_posted(a.id) > 0 then
    raise exception 'Post the depreciation of % up to % first', a.code, p_date;
  end if;
end $function$
;
