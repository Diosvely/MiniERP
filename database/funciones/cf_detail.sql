-- =====================================================================
-- erp.cf_detail · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0022_cash_flow   →   la vigente es la de 0022_cash_flow
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.cf_detail(p_company uuid, p_year integer, p_method text)
 RETURNS TABLE(line_code text, account_no text, account_name text, account_name_en text, amount numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
begin
  if p_method = 'indirect' then return query select * from erp.cf_indirect_detail(p_company, p_year);
  elsif p_method = 'direct' then return query select * from erp.cf_direct_detail(p_company, p_year);
  else raise exception 'Unknown cash flow method: %', p_method;
  end if;
end $function$
;
