-- =====================================================================
-- erp.provision_post · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0045_provisions   →   la vigente es la de 0045_provisions
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.provision_post(p_company uuid, p_date date, p_desc text, p_lines jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare v_entry uuid; x jsonb; n int := 0;
begin
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (p_company, erp.adjust_fiscal_year(p_company, p_date), p_date, left(p_desc, 250))
  returning id into v_entry;
  for x in select * from jsonb_array_elements(p_lines) loop
    if coalesce((x->>'debit')::numeric, 0) = 0 and coalesce((x->>'credit')::numeric, 0) = 0 then continue; end if;
    n := n + 1;
    insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description)
    values (v_entry, p_company, n, (x->>'account_id')::uuid, coalesce((x->>'debit')::numeric, 0), coalesce((x->>'credit')::numeric, 0), x->>'text');
  end loop;
  return v_entry;
end $function$
;
