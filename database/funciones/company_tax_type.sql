-- =====================================================================
-- erp.company_tax_type · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0082_tax_dashboard   →   la vigente es la de 0082_tax_dashboard
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.company_tax_type(p_company uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  select case tax_territory when 'canary_islands' then 'IGIC' else 'VAT' end from erp.companies where id = p_company;
$function$
;
