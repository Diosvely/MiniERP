-- =====================================================================
-- erp.tg_entry_asset_reverse · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0041_fixed_assets   →   la vigente es la de 0041_fixed_assets
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_entry_asset_reverse()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.reversal_of is not null and coalesce(current_setting('erp.asset_engine', true), '') <> 'on'
     and (exists (select 1 from erp.asset_depreciations where entry_id = new.reversal_of)
          or exists (select 1 from erp.fixed_assets where disposal_entry_id = new.reversal_of)) then
    raise exception 'This entry belongs to the fixed assets module: cancel it from Fixed assets';
  end if;
  return new;
end $function$
;
