-- =====================================================================
-- erp.import_account_name · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0021_journal_import   →   la vigente es la de 0021_journal_import
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.import_account_name(p_account_no text, p_name text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  select case
    when nullif(btrim(p_name), '') is null or p_name like '%*%' or p_name ilike 'nombre cuenta%' then
      coalesce((select t.name from erp.coa_template t where p_account_no like t.account_no || '%' and t.level >= 3
                order by t.level desc limit 1), 'Cuenta') || ' ' || p_account_no
    else btrim(p_name) end;
$function$
;
