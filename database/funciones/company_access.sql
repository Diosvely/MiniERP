-- =====================================================================
-- erp.company_access · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0027_members   →   la vigente es la de 0027_members
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.company_access(p_company uuid)
 RETURNS TABLE(user_id uuid, email text, role text, data_owner boolean, since timestamp with time zone, ai_calls_today integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
begin
  if not erp.is_owner() then raise exception 'Only the application owner can manage access'; end if;
  return query
  select cu.user_id, u.email::text, cu.role, cu.data_owner, cu.created_at,
         coalesce((select a.calls from erp.ai_usage a where a.user_id = cu.user_id and a.used_on = current_date), 0)
  from erp.company_users cu join auth.users u on u.id = cu.user_id
  where cu.company_id = p_company
  order by cu.created_at;
end $function$
;
