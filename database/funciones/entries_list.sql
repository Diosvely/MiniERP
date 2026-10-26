-- =====================================================================
-- erp.entries_list · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0070_entries_screen   →   la vigente es la de 0070_entries_screen
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.entries_list(p_company uuid, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_limit integer DEFAULT 500, p_offset integer DEFAULT 0)
 RETURNS TABLE(entry_id uuid, fiscal_year integer, entry_no integer, posting_date date, document_no text, description text, entry_type text, status text, total_debit numeric, total_credit numeric, lines integer, source text, state text, problem text, reversal_of_no integer, reversed_by_no integer, total_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  return query
  with e as (
    select j.*, count(*) over () as n
    from erp.journal_entries j
    where j.company_id = p_company
      and (p_from is null or j.posting_date >= p_from) and (p_to is null or j.posting_date <= p_to)
    order by j.posting_date desc, j.entry_no desc nulls first, j.created_at desc
    limit greatest(coalesce(p_limit, 500), 1) offset greatest(coalesce(p_offset, 0), 0))
  select e.id, fy.year::int, e.entry_no, e.posting_date, e.document_no, e.description, e.entry_type, e.status,
         coalesce(t.d, 0), coalesce(t.c, 0), coalesce(t.n, 0)::int, (select erp.entry_source(j2) from erp.journal_entries j2 where j2.id = e.id),
         case when e.status = 'posted' then 'posted' when p.problem is null then 'ok' else 'error' end, p.problem,
         ro.entry_no, rb.entry_no, e.n
  from e
  join erp.fiscal_years fy on fy.id = e.fiscal_year_id
  left join lateral (select sum(l.debit) d, sum(l.credit) c, count(*) n from erp.journal_lines l where l.entry_id = e.id) t on true
  left join lateral (select case when e.status = 'draft' then erp.draft_problem(e.id) end as problem) p on true
  left join erp.journal_entries ro on ro.id = e.reversal_of
  left join erp.journal_entries rb on rb.id = e.reversed_by
  order by e.posting_date desc, e.entry_no desc nulls first, e.created_at desc;
end $function$
;
