-- =====================================================================
-- erp.cancel_disposal · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0041_fixed_assets   →   la vigente es la de 0041_fixed_assets
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.cancel_disposal(p_asset uuid, p_date date DEFAULT NULL::date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare a erp.fixed_assets; v_no int;
begin
  select * into a from erp.fixed_assets where id = p_asset;
  if not found then raise exception 'Asset not found'; end if;
  if not erp.can_write(a.company_id) then raise exception 'No permission to register fixed assets in this company'; end if;
  if a.status <> 'disposed' then raise exception 'Asset % is not disposed', a.code; end if;
  perform set_config('erp.asset_engine', 'on', true);
  v_no := erp.reverse_entry(a.disposal_entry_id, coalesce(p_date, a.disposal_date), 'Baja anulada');
  perform set_config('erp.asset_engine', 'off', true);
  delete from erp.asset_depreciations where entry_id = a.disposal_entry_id;
  update erp.fixed_assets set status = 'active', disposal_date = null, disposal_price = null,
                              disposal_invoice_id = null, disposal_entry_id = null
  where id = a.id;
  return v_no;
end $function$
;
