-- =====================================================================
-- erp.revoke_company_access · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0027_members   →   la vigente es la de 0027_members
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.revoke_company_access(p_company uuid, p_user uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
begin
  if not erp.is_owner() then raise exception 'Only the application owner can manage access'; end if;
  if p_user = auth.uid() then raise exception 'You cannot remove your own access'; end if;
  delete from erp.company_users where company_id = p_company and user_id = p_user;
end $function$
;
