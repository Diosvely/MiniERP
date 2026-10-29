-- =====================================================================
-- erp.set_legal_form · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0060_equity_operations   →   la vigente es la de 0060_equity_operations
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.set_legal_form(p_company uuid, p_form text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
begin
  if not erp.is_admin(p_company) then raise exception 'Only the company admin can change the legal form'; end if;
  if p_form not in ('sa', 'sl') then raise exception 'Invalid legal form: %', p_form; end if;
  if exists (select 1 from erp.equity_operations where company_id = p_company and status = 'posted') then
    raise exception 'The company already has equity operations: undo them before changing the legal form';
  end if;
  update erp.companies set legal_form = p_form where id = p_company;
end $function$
;
