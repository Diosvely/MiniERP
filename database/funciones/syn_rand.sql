-- =====================================================================
-- erp.syn_rand · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0086_synthetic_companies   →   la vigente es la de 0086_synthetic_companies
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.syn_rand(p_seed integer, p_n integer)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  select ('x' || substr(md5(p_seed::text || ':' || p_n::text), 1, 8))::bit(32)::bigint::numeric / 4294967296;
$function$
;
