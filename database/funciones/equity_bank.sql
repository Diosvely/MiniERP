-- =====================================================================
-- erp.equity_bank · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0060_equity_operations   →   la vigente es la de 0060_equity_operations
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.equity_bank(p_company uuid, p_no text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare v uuid;
begin
  if nullif(btrim(p_no), '') is not null then
    select id into v from erp.gl_accounts where company_id = p_company and account_no = btrim(p_no) and account_type = 'posting' and account_no like '57%';
    if v is null then raise exception 'Bank account % does not exist (it must be a 57 subaccount)', p_no; end if;
    return v;
  end if;
  select id into v from erp.gl_accounts where company_id = p_company and account_type = 'posting' and account_no like '572%' order by account_no limit 1;
  return coalesce(v, erp.adjust_account(p_company, '572', 'Bancos e instituciones de crédito c/c vista, euros'));
end $function$
;
