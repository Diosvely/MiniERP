-- =====================================================================
-- erp.cancel_depreciation · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0041_fixed_assets   →   la vigente es la de 0041_fixed_assets
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.cancel_depreciation(p_entry uuid, p_date date DEFAULT NULL::date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare v_company uuid; v_no int; v_end date;
begin
  select d.company_id, max(d.period_end) into v_company, v_end from erp.asset_depreciations d where d.entry_id = p_entry group by d.company_id;
  if v_company is null then raise exception 'This entry is not a depreciation'; end if;
  if not erp.can_write(v_company) then raise exception 'No permission to register fixed assets in this company'; end if;
  if exists (select 1 from erp.fixed_assets a where a.disposal_entry_id = p_entry) then
    raise exception 'This depreciation belongs to a disposal: cancel the disposal instead';
  end if;
  if exists (select 1 from erp.asset_depreciations d where d.company_id = v_company and d.period_end > v_end) then
    raise exception 'Only the last depreciation can be cancelled';
  end if;
  perform set_config('erp.asset_engine', 'on', true);
  v_no := erp.reverse_entry(p_entry, coalesce(p_date, (select posting_date from erp.journal_entries where id = p_entry)), 'Amortización anulada');
  perform set_config('erp.asset_engine', 'off', true);
  delete from erp.asset_depreciations where entry_id = p_entry;
  return v_no;
end $function$
;
