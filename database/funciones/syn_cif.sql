-- =====================================================================
-- erp.syn_cif · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0086_synthetic_companies   →   la vigente es la de 0086_synthetic_companies
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.syn_cif(p_letter text, p_num integer)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  with d as (select lpad((p_num % 10000000)::text, 7, '0') as s),
  t as (select sum(case when i % 2 = 0 then substr(s, i, 1)::int
                        else (substr(s, i, 1)::int * 2) / 10 + (substr(s, i, 1)::int * 2) % 10 end) as total
        from d, generate_series(1, 7) i)
  select p_letter || s || ((10 - total % 10) % 10)::text from d, t;
$function$
;
