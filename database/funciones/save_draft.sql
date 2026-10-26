-- =====================================================================
-- erp.save_draft · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0070_entries_screen   →   la vigente es la de 0070_entries_screen
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.save_draft(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare v_company uuid := (p->>'company_id')::uuid; v_id uuid := (p->>'entry_id')::uuid; v_date date := (p->>'posting_date')::date;
        v_fy uuid; e erp.journal_entries;
begin
  if not erp.can_write(v_company) then raise exception 'No permission to save entries in this company'; end if;
  if v_date is null then raise exception 'The posting date is required'; end if;
  select id into v_fy from erp.fiscal_years where company_id = v_company and v_date between starting_date and ending_date;
  if v_fy is null then raise exception 'No fiscal year for date %', v_date; end if;
  if v_id is not null then
    select * into e from erp.journal_entries where id = v_id and company_id = v_company;
    if not found then raise exception 'Entry not found'; end if;
    if e.status <> 'draft' then raise exception 'Entry % is posted and cannot be changed', e.entry_no; end if;
    delete from erp.journal_lines where entry_id = v_id;
    update erp.journal_entries set fiscal_year_id = v_fy, posting_date = v_date, description = coalesce(nullif(btrim(p->>'description'), ''), 'Borrador'),
      document_no = nullif(btrim(p->>'document_no'), '') where id = v_id;
  else
    insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no)
    values (v_company, v_fy, v_date, coalesce(nullif(btrim(p->>'description'), ''), 'Borrador'), nullif(btrim(p->>'document_no'), ''))
    returning id into v_id;
  end if;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description)
  select v_id, v_company, x.ord, (x.l->>'gl_account_id')::uuid, round(coalesce((x.l->>'debit')::numeric, 0), 2),
         round(coalesce((x.l->>'credit')::numeric, 0), 2), nullif(btrim(x.l->>'description'), '')
  from jsonb_array_elements(coalesce(p->'lines', '[]'::jsonb)) with ordinality as x(l, ord)
  where (x.l->>'gl_account_id') is not null and (coalesce((x.l->>'debit')::numeric, 0) <> 0 or coalesce((x.l->>'credit')::numeric, 0) <> 0);
  return v_id;
end $function$
;
