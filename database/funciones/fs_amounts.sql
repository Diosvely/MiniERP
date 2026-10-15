-- =====================================================================
-- erp.fs_amounts · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0016_financial_statements   →   la vigente es la de 0016_financial_statements
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.fs_amounts(p_company uuid, p_year integer, p_statement text, p_to_date date DEFAULT NULL::date)
 RETURNS TABLE(code text, amount numeric)
 LANGUAGE sql
 STABLE
AS $function$
  with recursive up(code, ancestor) as (
    select l.code, l.code from erp.fs_lines l where l.statement = p_statement
    union all
    select up.code, p.parent
    from up join erp.fs_lines p on p.statement = p_statement and p.code = up.ancestor
    where p.parent is not null
  ), detail as (
    select line_code, sum(amount) as amount
    from erp.fs_classified_accounts(p_company, p_year, p_statement, p_to_date)
    group by line_code
  )
  select up.ancestor, coalesce(sum(d.amount), 0)
  from up left join detail d on d.line_code = up.code
  group by up.ancestor;
$function$
;
