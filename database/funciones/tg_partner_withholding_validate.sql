-- =====================================================================
-- erp.tg_partner_withholding_validate · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0033_withholding_rules   →   la vigente es la de 0033_withholding_rules
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_partner_withholding_validate()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  -- Se ejecuta después de partner_validate (orden alfabético), con el NIF ya normalizado
  if new.legal_form is null and new.tax_territory in ('mainland', 'canary_islands', 'ceuta_melilla') then
    new.legal_form := erp.legal_form_from_tax_id(new.vat_registration_no);
  end if;
  if new.withholding_code is not null then
    if new.partner_type not in ('vendor', 'creditor') then
      raise exception 'Withholding only applies to vendors and creditors';
    end if;
    if new.legal_form = 'company'
       and (select kind from erp.withholding_codes where code = new.withholding_code) = 'professional' then
      raise exception 'Professional withholding (IRPF) does not apply to companies';
    end if;
  end if;
  return new;
end $function$
;
