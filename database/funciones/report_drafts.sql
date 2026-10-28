-- =====================================================================
-- erp.report_drafts · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0074_report_simulation   →   la vigente es la de 0074_report_simulation
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.report_drafts(p_company uuid, p_year integer, p_to_date date DEFAULT NULL::date)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
  select count(*)::int
  from erp.journal_entries e
  join erp.fiscal_years fy on fy.id = e.fiscal_year_id and fy.year = p_year
  where e.company_id = p_company and e.status = 'draft'
    and (p_to_date is null or e.posting_date <= p_to_date)
    and erp.draft_ready(e.id);
$function$
;
