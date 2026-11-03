-- =====================================================================
-- erp.syn_nif · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0086_synthetic_companies   →   la vigente es la de 0086_synthetic_companies
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.syn_nif(p_num integer)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select lpad((p_num % 100000000)::text, 8, '0') || substr('TRWAGMYFPDXBNJZSQVHLCKE', (p_num % 100000000) % 23 + 1, 1);
$function$
;
