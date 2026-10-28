-- =====================================================================
-- erp.adjust_post · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0043_year_end_adjustments   →   la vigente es la de 0043_year_end_adjustments
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.adjust_post(p_company uuid, p_date date, p_desc text, p_doc text, p_debit uuid, p_credit uuid, p_amount numeric, p_partner uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare v_entry uuid;
begin
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no)
  values (p_company, erp.adjust_fiscal_year(p_company, p_date), p_date, left(p_desc, 250), left(p_doc, 60))
  returning id into v_entry;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, partner_id) values
    (v_entry, p_company, 1, p_debit, p_amount, 0, null),
    (v_entry, p_company, 2, p_credit, 0, p_amount, p_partner);
  return v_entry;
end $function$
;
