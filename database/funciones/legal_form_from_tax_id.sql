-- =====================================================================
-- erp.legal_form_from_tax_id · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0033_withholding_rules   →   la vigente es la de 0033_withholding_rules
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.legal_form_from_tax_id(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case
    when erp.normalize_tax_id(p) ~ '^([0-9]{8}|[KLMXYZ][0-9]{7})[A-Z]$' then 'individual'
    when erp.normalize_tax_id(p) ~ '^[ABCDEFGHJNPQRSUVW][0-9]{7}[0-9A-J]$' then 'company'
  end;
$function$
;
