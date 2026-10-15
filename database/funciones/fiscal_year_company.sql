-- =====================================================================
-- erp.fiscal_year_company · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0006_security_rls   →   la vigente es la de 0006_security_rls
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.fiscal_year_company(p_fiscal_year uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select company_id from erp.fiscal_years where id = p_fiscal_year;
$function$
;
