-- =====================================================================
-- erp.ensure_tax_account · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0010_tax_setup   →   la vigente es la de 0010_tax_setup
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.ensure_tax_account(p_company uuid, p_account_no text, p_name text, p_name_en text, INOUT status text, OUT account_id uuid)
 RETURNS record
 LANGUAGE plpgsql
AS $function$
declare
  a erp.gl_accounts;
begin
  select * into a from erp.gl_accounts where company_id = p_company and account_no = p_account_no;
  if found then
    if a.account_type <> 'posting' then
      raise exception 'Account % is a heading account', p_account_no;
    end if;
    account_id := a.id;
  else
    account_id := erp.create_posting_account(p_company, p_account_no, p_name, p_name_en);
    status := 'created';
  end if;
end $function$
;
