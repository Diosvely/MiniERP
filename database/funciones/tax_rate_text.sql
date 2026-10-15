-- =====================================================================
-- erp.tax_rate_text · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0010_tax_setup   →   la vigente es la de 0010_tax_setup
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tax_rate_text(p_rate numeric)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select replace(trim(trailing '.' from trim(trailing '0' from p_rate::text)), '.', ',');
$function$
;
