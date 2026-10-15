-- =====================================================================
-- erp.is_anonymous · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0015_guest_access   →   la vigente es la de 0015_guest_access
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.is_anonymous()
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false)
$function$
;
