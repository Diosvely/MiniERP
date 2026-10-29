-- =====================================================================
-- erp.set_vat_regime · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0019_reverse_charge_surcharge   →   la vigente es la de 0019_reverse_charge_surcharge
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.set_vat_regime(p_company uuid, p_regime text)
 RETURNS void
 LANGUAGE plpgsql
 SET jit TO 'off'
AS $function$
begin
  if not erp.is_admin(p_company) then
    raise exception 'Only the company admin can change the VAT regime';
  end if;
  update erp.companies set vat_regime = p_regime where id = p_company;
end $function$
;
