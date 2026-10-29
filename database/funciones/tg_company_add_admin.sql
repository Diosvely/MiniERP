-- =====================================================================
-- erp.tg_company_add_admin · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0001_core   →   la vigente es la de 0001_core
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_company_add_admin()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
begin
  if new.created_by is null then
    raise exception 'Set created_by (an auth.users id) when creating a company without a session';
  end if;
  insert into erp.company_users (company_id, user_id, role)
  values (new.id, new.created_by, 'admin');
  return new;
end $function$
;
