-- =====================================================================
-- erp.grant_company_access · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0027_members   →   la vigente es la de 0027_members
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.grant_company_access(p_company uuid, p_email text, p_role text, p_data_owner boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare v_user uuid;
begin
  if not erp.is_owner() then raise exception 'Only the application owner can manage access'; end if;
  if p_role not in ('admin', 'accountant', 'viewer') then raise exception 'Unknown role: %', p_role; end if;
  select id into v_user from auth.users where lower(email) = lower(trim(p_email));
  if v_user is null then raise exception 'No registered user with email %', p_email; end if;
  if v_user = auth.uid() then raise exception 'You already have full access'; end if;
  insert into erp.company_users (company_id, user_id, role, data_owner)
  values (p_company, v_user, p_role, coalesce(p_data_owner, false))
  on conflict (company_id, user_id) do update set role = excluded.role, data_owner = excluded.data_owner;
  return v_user;
end $function$
;
