-- =====================================================================
-- erp.fs_line_accounts · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0016_financial_statements   →   la vigente es la de 0016_financial_statements
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.fs_line_accounts(p_company uuid, p_year integer, p_statement text, p_code text, p_to_date date DEFAULT NULL::date)
 RETURNS TABLE(account_no text, account_name text, account_name_en text, line_code text, amount numeric)
 LANGUAGE sql
 STABLE
AS $function$
  with recursive below(code) as (
    select p_code
    union all
    select l.code from erp.fs_lines l join below b on l.parent = b.code where l.statement = p_statement
  )
  select c.account_no, c.account_name, c.account_name_en, c.line_code, c.amount
  from erp.fs_classified_accounts(p_company, p_year, p_statement, p_to_date) c
  where c.line_code in (select code from below)
  order by c.account_no;
$function$
;
