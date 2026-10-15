-- =====================================================================
-- erp.is_settlement_entry · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0012_tax_settlement 0017_year_closing   →   la vigente es la de 0017_year_closing
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.is_settlement_entry(p_entry uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select exists (select 1 from erp.tax_settlements s
                 join erp.journal_entries e on e.id = p_entry
                 where s.entry_id = e.id or s.entry_id = e.reversal_of)
      or erp.is_year_closing_entry(p_entry);
$function$
;
