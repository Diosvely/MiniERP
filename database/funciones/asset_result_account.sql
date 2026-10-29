-- =====================================================================
-- erp.asset_result_account · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0041_fixed_assets   →   la vigente es la de 0041_fixed_assets
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.asset_result_account(p_company uuid, p_asset_no text, p_result numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  v_digits int := (select posting_account_digits from erp.companies where id = p_company);
  v_pgc    text := case when p_result < 0 then '67' else '77' end || substr(p_asset_no, 2, 1);
  v_no     text := rpad(v_pgc, v_digits - 1, '0') || '1';
  v_id     uuid;
begin
  select id into v_id from erp.gl_accounts where company_id = p_company and account_no = v_no;
  if v_id is null then
    perform erp.create_posting_account(p_company, v_no, (select name from erp.gl_accounts where company_id = p_company and account_no = v_pgc));
    select id into v_id from erp.gl_accounts where company_id = p_company and account_no = v_no;
  end if;
  return v_id;
end $function$
;
