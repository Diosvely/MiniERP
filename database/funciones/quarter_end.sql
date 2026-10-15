-- =====================================================================
-- erp.quarter_end · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0012_tax_settlement   →   la vigente es la de 0012_tax_settlement
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.quarter_end(p_year integer, p_quarter integer)
 RETURNS date
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select (make_date(p_year, 3 * (p_quarter - 1) + 1, 1) + interval '3 months' - interval '1 day')::date
$function$
;
