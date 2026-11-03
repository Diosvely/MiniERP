-- =====================================================================
-- erp.syn_int · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0086_synthetic_companies   →   la vigente es la de 0086_synthetic_companies
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.syn_int(p_seed integer, p_n integer, a integer, b integer)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  select a + floor(erp.syn_rand(p_seed, p_n) * (b - a + 1))::int;
$function$
;
