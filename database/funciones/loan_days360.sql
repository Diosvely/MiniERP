-- =====================================================================
-- erp.loan_days360 · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0062_loans   →   la vigente es la de 0062_loans
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.loan_days360(p_from date, p_to date)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select (extract(year from p_to)::int - extract(year from p_from)::int) * 360
       + (extract(month from p_to)::int - extract(month from p_from)::int) * 30
       + (least(extract(day from p_to)::int, 30) - least(extract(day from p_from)::int, 30));
$function$
;
