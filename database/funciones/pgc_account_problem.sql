-- =====================================================================
-- erp.pgc_account_problem · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0056_grader_fixes   →   la vigente es la de 0056_grader_fixes
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.pgc_account_problem(p_account text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  select case
    when coalesce(btrim(p_account), '') !~ '^[0-9]+$' then 'invalid'
    when length(btrim(p_account)) <= 3
         and not exists (select 1 from erp.coa_template t where t.account_no = btrim(p_account)) then 'not_in_pgc'
    when length(btrim(p_account)) > 3
         and not exists (select 1 from erp.coa_template t where t.account_no = left(btrim(p_account), 3)) then 'not_in_pgc'
  end;
$function$
;
