-- =====================================================================
-- erp.synthetic_run · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0087_synthetic_batches   →   la vigente es la de 0087_synthetic_batches
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.synthetic_run(p_company uuid)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'erp', 'public'
AS $function$
  select erp.synthetic_step(p_company, 1000000);
$function$
;
