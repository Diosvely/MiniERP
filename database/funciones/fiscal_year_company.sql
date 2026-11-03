-- =====================================================================
-- erp.fiscal_year_company · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0006_security_rls 0085_permissions_ownership   →   la vigente es la de 0085_permissions_ownership
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.fiscal_year_company(p_fiscal_year uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select company_id from erp.fiscal_years where id = p_fiscal_year and erp.can_read(company_id);
$function$
;
