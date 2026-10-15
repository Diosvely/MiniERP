-- =====================================================================
-- erp.check_tax_account · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0010_tax_setup   →   la vigente es la de 0010_tax_setup
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.check_tax_account(p_company uuid, p_account uuid, p_prefix text, p_role text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  a erp.gl_accounts;
begin
  if p_account is null then return; end if;
  select * into a from erp.gl_accounts where id = p_account;
  if a.company_id is distinct from p_company then
    raise exception 'The % account does not belong to this company', p_role;
  end if;
  if a.account_type <> 'posting' then
    raise exception 'The % account % must be a posting account', p_role, a.account_no;
  end if;
  if a.account_no not like p_prefix || '%' then
    raise exception 'The % account % must start with %', p_role, a.account_no, p_prefix;
  end if;
end $function$
;
