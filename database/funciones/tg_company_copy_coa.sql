-- =====================================================================
-- erp.tg_company_copy_coa · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0002_chart_of_accounts   →   la vigente es la de 0002_chart_of_accounts
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_company_copy_coa()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
begin
  insert into erp.gl_accounts (company_id, account_no, name, name_en, account_type, template_account, account_category)
  select new.id, t.account_no, t.name, t.name_en, 'heading', t.account_no, t.account_category
  from erp.coa_template t;
  return new;
end $function$
;
