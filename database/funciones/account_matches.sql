-- =====================================================================
-- erp.account_matches · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0056_grader_fixes   →   la vigente es la de 0056_grader_fixes
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.account_matches(p_answer text, p_expected text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select p_answer like p_expected || '%'
     and not exists (select 1 from erp.pgc_distinct_accounts d
                     where d.account_no like p_expected || '_%' and p_answer like d.account_no || '%');
$function$
;
