-- =====================================================================
-- erp.case_progress · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0067_case_screen   →   la vigente es la de 0067_case_screen
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.case_progress(p_company uuid)
 RETURNS TABLE(n integer, phase text, date_label text, date_label_en text, title text, title_en text, entry text, why text, why_en text, screen text, checklist_code text, status text, entries jsonb)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'erp', 'public'
AS $function$
declare v_case erp.cases; v_cl jsonb;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  select * into v_case from erp.cases where key = (select case_key from erp.companies where id = p_company);
  if not found then raise exception 'No case loaded in this company'; end if;
  select jsonb_object_agg(k.code, k.status) into v_cl from erp.closing_checklist(p_company, v_case.year) k;
  return query
  select s.n, s.phase, s.date_label, s.date_label_en, s.title, s.title_en, s.entry, s.why, s.why_en, s.screen, s.checklist_code,
         case when exists (select 1 from erp.case_entries ce where ce.company_id = p_company and ce.n = s.n) then 'done'
              when s.n = 14 and exists (select 1 from erp.case_entries ce where ce.company_id = p_company and ce.n = 13) then 'done'
              when s.checklist_code is not null and v_cl->>s.checklist_code in ('done', 'na') then 'done'
              else 'pending' end,
         coalesce((select jsonb_agg(jsonb_build_object('entry_id', j.id, 'year', fy.year, 'entry_no', j.entry_no, 'date', j.posting_date,
                                                       'description', j.description) order by j.posting_date, j.entry_no)
                   from erp.case_entries ce join erp.journal_entries j on j.id = ce.entry_id
                   join erp.fiscal_years fy on fy.id = j.fiscal_year_id
                   where ce.company_id = p_company and ce.n = s.n), '[]'::jsonb)
  from erp.case_steps s where s.case_key = v_case.key
  order by s.n;
end $function$
;
