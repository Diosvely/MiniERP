-- =====================================================================
-- erp.counts_in_reports · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0074_report_simulation   →   la vigente es la de 0074_report_simulation
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.counts_in_reports(p_status text, p_entry uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select p_status = 'posted'
      or (p_status = 'draft' and erp.simulating() and erp.draft_ready(p_entry));
$function$
;
