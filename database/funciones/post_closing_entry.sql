-- =====================================================================
-- erp.post_closing_entry · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0017_year_closing   →   la vigente es la de 0017_year_closing
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.post_closing_entry(p_company uuid, p_fiscal_year uuid, p_date date, p_type text, p_description text, p_document text, p_lines jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SET jit TO 'off'
AS $function$
declare
  v_entry uuid;
begin
  if coalesce(current_setting('erp.year_closing_engine', true), '') <> 'on' then
    raise exception 'Closing entries are created only with close_fiscal_year()';
  end if;
  if jsonb_array_length(p_lines) = 0 then
    return null;
  end if;
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no, entry_type)
  values (p_company, p_fiscal_year, p_date, p_description, p_document, p_type)
  returning id into v_entry;

  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit)
  select v_entry, p_company, x.ord, g.id, (x.l->>'debit')::numeric, (x.l->>'credit')::numeric
  from jsonb_array_elements(p_lines) with ordinality as x(l, ord)
  join erp.gl_accounts g on g.company_id = p_company and g.account_no = x.l->>'account_no';
  -- Los saldos de 472/477 que pasan de año no son operaciones del libro registro
  update erp.journal_lines set tax_code = null where entry_id = v_entry;

  perform erp.post_entry(v_entry);
  return v_entry;
end $function$
;
