-- =====================================================================
-- erp.operation_for_lines · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0054_operations_exercises   →   la vigente es la de 0054_operations_exercises
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.operation_for_lines(p_lines jsonb)
 RETURNS SETOF erp.operations
 LANGUAGE sql
 STABLE
AS $function$
  select o.* from erp.operations o
  where not exists (
    select 1 from unnest(o.accounts) a
    where not exists (select 1 from jsonb_array_elements(p_lines) l where coalesce(l->>'account_no', '') like a || '%'))
  order by cardinality(o.accounts) desc, (select sum(length(a)) from unnest(o.accounts) a) desc, o.sort
  limit 1;
$function$
;
