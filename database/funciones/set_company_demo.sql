-- =====================================================================
-- erp.set_company_demo · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0027_members 0085_permissions_ownership 0086_synthetic_companies   →   la vigente es la de 0086_synthetic_companies
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.set_company_demo(p_company uuid, p_demo boolean, p_credit text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
begin
  if not (erp.can_manage_access(p_company) or erp.is_data_owner(p_company)) then
    raise exception 'Only the application owner or the data owner can publish a company as demo';
  end if;
  if p_demo and exists (select 1 from erp.companies where id = p_company and synthetic_seed is not null) then
    raise exception 'A synthetic company cannot be published as demo';
  end if;
  update erp.companies
  set is_demo = p_demo, data_credit = coalesce(nullif(trim(p_credit), ''), data_credit)
  where id = p_company;
end $function$
;
