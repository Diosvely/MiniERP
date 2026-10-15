-- =====================================================================
-- erp.concepts_for_account · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0038_concepts   →   la vigente es la de 0038_concepts
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.concepts_for_account(p_account_no text)
 RETURNS SETOF erp.concepts
 LANGUAGE sql
 STABLE
AS $function$
  select c.* from erp.concepts c
  where exists (select 1 from unnest(c.pgc) p where p_account_no like p || '%')
  order by (select max(length(p)) from unnest(c.pgc) p where p_account_no like p || '%') desc, c.sort;
$function$
;
