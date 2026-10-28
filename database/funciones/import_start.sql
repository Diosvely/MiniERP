-- =====================================================================
-- erp.import_start · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0021_journal_import 0072_temporary_companies   →   la vigente es la de 0072_temporary_companies
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.import_start(p_name text, p_digits integer, p_territory text, p_industry text, p_source text, p_file_name text DEFAULT NULL::text)
 RETURNS TABLE(company_id uuid, batch_id uuid)
 LANGUAGE plpgsql
 SET jit TO 'off'
AS $function$
declare
  v_company uuid;
  v_batch   uuid;
begin
  perform erp.temp_cleanup(20000);   -- antes de mirar si cabe, se limpia lo caducado (por si pg_cron no está)
  insert into erp.companies (name, industry, tax_territory, posting_account_digits, created_by, temporary)
  values (p_name, p_industry, p_territory, p_digits, auth.uid(), not erp.is_trusted())
  returning id into v_company;
  insert into erp.import_batches (company_id, source, file_name)
  values (v_company, p_source, p_file_name)
  returning id into v_batch;
  return query select v_company, v_batch;
end $function$
;
