-- =====================================================================
-- erp.tg_partner_equivalence · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0019_reverse_charge_surcharge   →   la vigente es la de 0019_reverse_charge_surcharge
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_partner_equivalence()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.equivalence_surcharge and (new.partner_type not in ('customer', 'debtor') or new.tax_territory <> 'mainland') then
    raise exception 'Only customers from mainland Spain can be under the equivalence surcharge';
  end if;
  return new;
end $function$
;
