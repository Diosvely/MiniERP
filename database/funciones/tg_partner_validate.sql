-- =====================================================================
-- erp.tg_partner_validate · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0009_partners   →   la vigente es la de 0009_partners
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_partner_validate()
 RETURNS trigger
 LANGUAGE plpgsql
 SET jit TO 'off'
AS $function$
begin
  new.vat_registration_no := erp.normalize_tax_id(new.vat_registration_no);
  new.name := btrim(new.name);
  if new.name = '' then
    raise exception 'Partner name is required';
  end if;
  if new.vat_registration_no is not null
     and new.tax_territory in ('mainland', 'canary_islands', 'ceuta_melilla')
     and not erp.valid_spanish_tax_id(new.vat_registration_no) then
    raise exception 'Invalid Spanish tax ID (NIF/NIE/CIF): %', new.vat_registration_no;
  end if;
  return new;
end $function$
;
