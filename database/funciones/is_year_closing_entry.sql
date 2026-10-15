-- =====================================================================
-- erp.is_year_closing_entry · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0017_year_closing   →   la vigente es la de 0017_year_closing
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.is_year_closing_entry(p_entry uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select exists (select 1 from erp.year_closings c
                 join erp.journal_entries e on e.id = p_entry
                 where coalesce(e.reversal_of, e.id) in (c.closing_pl_entry_id, c.closing_entry_id, c.opening_entry_id));
$function$
;
