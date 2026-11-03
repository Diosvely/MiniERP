-- =====================================================================
-- erp.synthetic_version · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0086_synthetic_companies   →   la vigente es la de 0086_synthetic_companies
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.synthetic_version()
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$ select 'g1' $function$
;
