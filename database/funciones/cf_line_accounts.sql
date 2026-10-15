-- =====================================================================
-- erp.cf_line_accounts · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0022_cash_flow   →   la vigente es la de 0022_cash_flow
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.cf_line_accounts(p_company uuid, p_year integer, p_method text, p_code text)
 RETURNS TABLE(account_no text, account_name text, account_name_en text, amount numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  if p_method not in ('indirect', 'direct') then raise exception 'Unknown cash flow method: %', p_method; end if;
  return query
  with recursive below(code) as (
    select p_code
    union all
    select l.code from erp.cf_lines l join below b on l.parent = b.code where l.method = p_method
  )
  select x.account_no, x.account_name, x.account_name_en, sum(x.amount)
  from erp.cf_detail(p_company, p_year, p_method) x
  where x.line_code in (select code from below)
  group by 1, 2, 3
  having sum(x.amount) <> 0
  order by 1;
end $function$
;
