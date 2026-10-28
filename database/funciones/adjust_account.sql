-- =====================================================================
-- erp.adjust_account · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0043_year_end_adjustments   →   la vigente es la de 0043_year_end_adjustments
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.adjust_account(p_company uuid, p_prefix text, p_name text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  v_no text := rpad(p_prefix, (select posting_account_digits from erp.companies where id = p_company) - 1, '0') || '1';
  v_id uuid;
begin
  select id into v_id from erp.gl_accounts where company_id = p_company and account_no = v_no;
  if v_id is null then v_id := erp.create_posting_account(p_company, v_no, p_name); end if;
  return v_id;
end $function$
;
