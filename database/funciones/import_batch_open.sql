-- =====================================================================
-- erp.import_batch_open · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0021_journal_import   →   la vigente es la de 0021_journal_import
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.import_batch_open(p_batch uuid, p_company uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select exists (select 1 from erp.import_batches b
                 where b.id = p_batch and b.company_id = p_company and b.status = 'staging');
$function$
;
