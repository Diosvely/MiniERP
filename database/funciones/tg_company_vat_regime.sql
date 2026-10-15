-- =====================================================================
-- erp.tg_company_vat_regime · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0019_reverse_charge_surcharge   →   la vigente es la de 0019_reverse_charge_surcharge
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_company_vat_regime()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.vat_regime = 'equivalence_surcharge' and new.tax_territory <> 'mainland' then
    raise exception 'The equivalence surcharge only exists for VAT (mainland Spain)';
  end if;
  return new;
end $function$
;
