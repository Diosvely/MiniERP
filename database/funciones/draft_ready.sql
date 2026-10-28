-- =====================================================================
-- erp.draft_ready · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0074_report_simulation   →   la vigente es la de 0074_report_simulation
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.draft_ready(p_entry uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select exists (select 1 from erp.journal_entries e
                 where e.id = p_entry and e.status = 'draft' and erp.can_read(e.company_id))
     and erp.draft_problem(p_entry) is null;
$function$
;
