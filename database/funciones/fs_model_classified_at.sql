-- =====================================================================
-- erp.fs_model_classified_at · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0089_balance_models   →   la vigente es la de 0089_balance_models
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.fs_model_classified_at(p_company uuid, p_year integer, p_model text, p_dates date[])
 RETURNS TABLE(at date, account_no text, account_name text, account_name_en text, balance numeric, line_code text, amount numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO 'erp', 'public'
AS $function$
  select c.at, c.account_no, c.account_name, c.account_name_en, c.balance, c.line_code, c.amount
  from erp.fs_classified_at(p_company, p_year, 'balance', p_dates) c
  where p_model = 'pymes'
  union all
  select c.at, c.account_no, c.account_name, c.account_name_en, c.balance, m.line,
         c.balance * case l.side when 'debit' then 1 else -1 end
  from erp.fs_classified_at(p_company, p_year, 'balance', p_dates) c
  cross join lateral (
    select case when c.balance >= 0 then fm.debit_line else fm.credit_line end as line
    from erp.fs_model_mapping fm
    where fm.model = p_model and c.account_no like fm.prefix || '%'
    order by length(fm.prefix) desc limit 1) m
  join erp.fs_model_lines l on l.model = p_model and l.code = m.line
  where p_model <> 'pymes';
$function$
;
