-- =====================================================================
-- erp.simulating · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0074_report_simulation   →   la vigente es la de 0074_report_simulation
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.simulating()
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce(nullif(current_setting('erp.simulate', true), ''), 'off') = 'on';
$function$
;
