-- =====================================================================
-- erp.reverse_entry · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0004_journal_entries 0014_journal_reverse 0017_year_closing   →   la vigente es la de 0017_year_closing
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.reverse_entry(p_entry uuid, p_posting_date date DEFAULT NULL::date, p_reason text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
declare
  v_e     erp.journal_entries;
  v_date  date;
  v_fy    uuid;
  v_new   uuid;
  v_no    int;
begin
  select * into v_e from erp.journal_entries where id = p_entry;
  if not found then raise exception 'Entry not found (or no permission)'; end if;
  if not erp.can_write(v_e.company_id) then
    raise exception 'No permission to reverse entries in this company';
  end if;
  if v_e.status <> 'posted' then
    raise exception 'Only posted entries can be reversed; a draft can simply be deleted';
  end if;
  if v_e.reversed_by is not null then raise exception 'Entry % is already reversed', v_e.entry_no; end if;
  if v_e.reversal_of is not null then raise exception 'A reversal entry cannot be reversed'; end if;
  if coalesce(current_setting('erp.tax_settlement_engine', true), '') <> 'on'
     and exists (select 1 from erp.tax_settlements s where s.entry_id = p_entry) then
    raise exception 'This entry belongs to a tax settlement: use "Undo settlement" instead';
  end if;
  if coalesce(current_setting('erp.year_closing_engine', true), '') <> 'on' and erp.is_year_closing_entry(p_entry) then
    raise exception 'This entry belongs to a year-end closing: reopen the fiscal year instead';
  end if;

  v_date := coalesce(p_posting_date, v_e.posting_date);
  if v_date < v_e.posting_date then
    raise exception 'The reversal date cannot be earlier than the original entry (%)', v_e.posting_date;
  end if;
  select id into v_fy from erp.fiscal_years
  where company_id = v_e.company_id and v_date between starting_date and ending_date;
  if v_fy is null then raise exception 'No fiscal year for date %', v_date; end if;

  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no, entry_type,
                                   reversal_of, reversal_reason)
  values (v_e.company_id, v_fy, v_date,
          'Anulación del asiento ' || v_e.entry_no || ': ' || v_e.description
            || coalesce(' · ' || nullif(btrim(p_reason), ''), ''),
          v_e.document_no, v_e.entry_type, v_e.id, nullif(btrim(p_reason), ''))
  returning id into v_new;

  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description,
                                 partner_id, tax_code, tax_base)
  select v_new, company_id, line_no, gl_account_id, credit, debit, description,
         partner_id, tax_code, -tax_base
  from erp.journal_lines where entry_id = v_e.id;
  if erp.is_year_closing_entry(v_e.id) then
    update erp.journal_lines set tax_code = null where entry_id = v_new;
  end if;

  v_no := erp.post_entry(v_new);
  update erp.journal_entries set reversed_by = v_new where id = v_e.id;
  return v_no;
end $function$
;
