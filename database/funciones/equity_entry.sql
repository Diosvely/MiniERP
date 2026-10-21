-- =====================================================================
-- erp.equity_entry · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0060_equity_operations   →   la vigente es la de 0060_equity_operations
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.equity_entry(p_company uuid, p_date date, p_desc text, p_doc text, p_lines jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare v_entry uuid;
begin
  if not exists (select 1 from jsonb_array_elements(p_lines) l where coalesce((l->>'debit')::numeric, 0) + coalesce((l->>'credit')::numeric, 0) > 0) then
    return null;
  end if;
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no)
  values (p_company, erp.adjust_fiscal_year(p_company, p_date), p_date, left(p_desc, 250), p_doc)
  returning id into v_entry;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit)
  select v_entry, p_company, row_number() over (), (l->>'account_id')::uuid, coalesce((l->>'debit')::numeric, 0), coalesce((l->>'credit')::numeric, 0)
  from jsonb_array_elements(p_lines) l where coalesce((l->>'debit')::numeric, 0) + coalesce((l->>'credit')::numeric, 0) > 0;
  perform erp.adjust_finish(v_entry);
  return v_entry;
end $function$
;
