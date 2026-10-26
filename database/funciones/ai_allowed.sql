-- =====================================================================
-- erp.ai_allowed · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0027_members 0072_temporary_companies   →   la vigente es la de 0072_temporary_companies
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.ai_allowed(p_company uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select (erp.is_owner() and erp.can_read(p_company)) or erp.is_data_owner(p_company)
      or exists (select 1 from erp.companies c where c.id = p_company and c.temporary and c.created_by = auth.uid()
                 and not erp.temp_expired(c.expires_at, c.last_seen_at));
$function$
;
