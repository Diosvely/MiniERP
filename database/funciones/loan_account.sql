-- =====================================================================
-- erp.loan_account · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0062_loans   →   la vigente es la de 0062_loans
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.loan_account(p_company uuid, p_no text, p_default text, p_name text, p_allowed text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare v uuid;
begin
  if nullif(btrim(p_no), '') is not null then
    select id into v from erp.gl_accounts
    where company_id = p_company and account_no = btrim(p_no) and account_type = 'posting' and account_no ~ p_allowed;
    if v is null then raise exception 'Account % does not exist or is not valid here (%)', p_no, p_allowed; end if;
    return v;
  end if;
  return erp.adjust_account(p_company, p_default, p_name);
end $function$
;
