-- =====================================================================
-- erp.result_account_no · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0017_year_closing   →   la vigente es la de 0017_year_closing
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.result_account_no(p_company uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce(
    (select account_no from erp.gl_accounts
     where company_id = p_company and account_type = 'posting' and template_account = '129'
     order by account_no limit 1),
    (select rpad('129', posting_account_digits, '0') from erp.companies where id = p_company));
$function$
;
