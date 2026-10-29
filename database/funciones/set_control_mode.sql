-- =====================================================================
-- erp.set_control_mode · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0036_controlled_accounts   →   la vigente es la de 0036_controlled_accounts
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.set_control_mode(p_company uuid, p_mode text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
begin
  if not erp.is_admin(p_company) then raise exception 'Only the company admin can change the control mode'; end if;
  if p_mode not in ('strict', 'guided') then raise exception 'Invalid control mode: %', p_mode; end if;
  update erp.companies set control_mode = p_mode where id = p_company;
end $function$
;
