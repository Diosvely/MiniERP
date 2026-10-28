-- =====================================================================
-- erp.fs_line_accounts · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0016_financial_statements 0074_report_simulation   →   la vigente es la de 0074_report_simulation
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.fs_line_accounts(p_company uuid, p_year integer, p_statement text, p_code text, p_to_date date DEFAULT NULL::date, p_drafts boolean DEFAULT false)
 RETURNS TABLE(account_no text, account_name text, account_name_en text, line_code text, amount numeric)
 LANGUAGE plpgsql
 STABLE
 SET jit TO 'off'
AS $function$
#variable_conflict use_column
declare v_prev text := coalesce(nullif(current_setting('erp.simulate', true), ''), 'off');
begin
  if p_drafts then perform set_config('erp.simulate', 'on', true); end if;
  return query
  with recursive below(code) as (
    select p_code
    union all
    select l.code from erp.fs_lines l join below b on l.parent = b.code where l.statement = p_statement
  )
  select c.account_no, c.account_name, c.account_name_en, c.line_code, c.amount
  from erp.fs_classified_accounts(p_company, p_year, p_statement, p_to_date) c
  where c.line_code in (select b.code from below b)
  order by c.account_no;
  perform set_config('erp.simulate', v_prev, true);
end $function$
;
