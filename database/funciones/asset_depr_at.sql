-- =====================================================================
-- erp.asset_depr_at · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0046_asset_impairment   →   la vigente es la de 0046_asset_impairment
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.asset_depr_at(p_asset uuid, p_date date)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
 SET jit TO 'off'
AS $function$
declare
  a      erp.fixed_assets;
  e      record;
  v_t    date;        -- inicio del tramo
  v_d    numeric;     -- amortizado al inicio del tramo
  v_rem  numeric;     -- lo que queda por amortizar al inicio del tramo
  v_at   numeric;
begin
  select * into a from erp.fixed_assets where id = p_asset;
  if not found or p_date < a.start_date then return 0; end if;
  if not exists (select 1 from erp.asset_events x where x.asset_id = a.id and x.event_date <= p_date) then
    return erp.asset_accumulated_at(erp.asset_cost_at(a.id, p_date), a.residual_value, a.useful_life_months, a.start_date, p_date);
  end if;
  v_t := a.start_date - 1; v_d := 0;      -- el día antes de empezar: 0 meses transcurridos
  v_rem := erp.asset_cost_at(a.id, a.start_date - 1) - a.residual_value;
  for e in select * from erp.asset_events x where x.asset_id = a.id and x.event_date <= p_date order by x.event_date, x.created_at loop
    v_at := erp.asset_tranche_at(a.useful_life_months, a.start_date, v_t, v_d, v_rem, e.event_date);
    v_rem := v_rem - (v_at - v_d)
             + case e.kind when 'impairment' then -e.amount when 'reversal' then e.amount else e.amount end;
    v_d := v_at; v_t := e.event_date;
  end loop;
  return erp.asset_tranche_at(a.useful_life_months, a.start_date, v_t, v_d, v_rem, p_date);
end $function$
;
