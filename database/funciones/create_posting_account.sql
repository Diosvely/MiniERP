-- =====================================================================
-- erp.create_posting_account · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0002_chart_of_accounts   →   la vigente es la de 0002_chart_of_accounts
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.create_posting_account(p_company uuid, p_account_no text, p_name text, p_name_en text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE sql
AS $function$
  insert into erp.gl_accounts (company_id, account_no, name, name_en, account_type, template_account, account_category)
  values (p_company, p_account_no, p_name, p_name_en, 'posting', '', '')   -- el trigger rellena template_account y account_category
  returning id;
$function$
;
