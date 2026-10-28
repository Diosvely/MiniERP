-- =====================================================================
-- erp.fs_classified_accounts · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0016_financial_statements 0017_year_closing 0074_report_simulation 0075_dashboards   →   la vigente es la de 0075_dashboards
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.fs_classified_accounts(p_company uuid, p_year integer, p_statement text, p_to_date date DEFAULT NULL::date)
 RETURNS TABLE(account_no text, account_name text, account_name_en text, balance numeric, line_code text, amount numeric)
 LANGUAGE sql
 STABLE
AS $function$
  select c.account_no, c.account_name, c.account_name_en, c.balance, c.line_code, c.amount
  from erp.fs_classified_at(p_company, p_year, p_statement, array[p_to_date]) c;
$function$
;
