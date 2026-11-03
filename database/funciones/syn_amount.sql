-- =====================================================================
-- erp.syn_amount · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0086_synthetic_companies   →   la vigente es la de 0086_synthetic_companies
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.syn_amount(p_seed integer, p_n integer, a numeric, b numeric)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  select round(a + erp.syn_rand(p_seed, p_n) * (b - a), 2);
$function$
;
