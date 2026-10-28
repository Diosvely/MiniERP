-- =====================================================================
-- erp.cancel_tax_settlement · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0012_tax_settlement   →   la vigente es la de 0012_tax_settlement
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.cancel_tax_settlement(p_settlement uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET jit TO 'off'
AS $function$
declare
  s erp.tax_settlements;
begin
  select * into s from erp.tax_settlements where id = p_settlement and status = 'posted';
  if not found then
    raise exception 'Settlement not found';
  end if;
  if not erp.can_write(s.company_id) then
    raise exception 'No permission to cancel tax settlements in this company';
  end if;
  if exists (select 1 from erp.tax_settlements x where x.company_id = s.company_id and x.tax_type = s.tax_type
             and x.status = 'posted' and (x.year, x.quarter) > (s.year, s.quarter)) then
    raise exception 'Only the last settlement can be cancelled';
  end if;
  perform set_config('erp.tax_settlement_engine', 'on', true);
  if s.entry_id is not null then
    perform erp.reverse_entry(s.entry_id);
  end if;
  update erp.tax_settlements set status = 'cancelled' where id = s.id;
  perform set_config('erp.tax_settlement_engine', 'off', true);
end $function$
;
