-- =====================================================================
-- erp.asset_account_pair · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0041_fixed_assets   →   la vigente es la de 0041_fixed_assets
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.asset_account_pair(p_company uuid, p_asset_no text, p_kind text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
-- 2x → su amortización acumulada (28x: 21x → 281x, 20x → 280x, 22x → 282x) o su gasto (68x)
declare
  v_digits int := (select posting_account_digits from erp.companies where id = p_company);
  v_no     text;
  v_id     uuid;
begin
  v_no := case p_kind
    when 'depreciation' then rpad('28' || substr(p_asset_no, 2, 1) || substr(p_asset_no, 3, 1), v_digits - 1, '0') || '1'
    else rpad('68' || substr(p_asset_no, 2, 1), v_digits - 1, '0') || '1' end;
  select id into v_id from erp.gl_accounts where company_id = p_company and account_no = v_no;
  if v_id is null then
    perform erp.create_posting_account(p_company, v_no,
      case p_kind when 'depreciation' then 'Amortización acumulada · ' || (select name from erp.gl_accounts where company_id = p_company and account_no = p_asset_no)
                  else (select name from erp.gl_accounts where company_id = p_company and account_no = rpad(left(v_no, 3), 3, '0')) end);
    select id into v_id from erp.gl_accounts where company_id = p_company and account_no = v_no;
  end if;
  return v_id;
end $function$
;
