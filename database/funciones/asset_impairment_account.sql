-- =====================================================================
-- erp.asset_impairment_account · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0046_asset_impairment   →   la vigente es la de 0046_asset_impairment
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.asset_impairment_account(p_company uuid, p_asset_no text, p_kind text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare v_prefix text; v_name text;
begin
  v_prefix := case p_kind when 'allowance' then '29' || substr(p_asset_no, 2, 2)
                          when 'expense' then '69' || substr(p_asset_no, 2, 1) else '79' || substr(p_asset_no, 2, 1) end;
  v_name := case p_kind when 'allowance' then 'Deterioro de valor · ' || (select name from erp.gl_accounts where company_id = p_company and account_no = p_asset_no)
                        else (select t.name from erp.coa_template t where t.account_no = left(v_prefix, 3)) end;
  return erp.adjust_account(p_company, v_prefix, v_name);
end $function$
;
