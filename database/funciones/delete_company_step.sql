-- =====================================================================
-- erp.delete_company_step · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0029_performance 0035_payments 0041_fixed_assets 0043_year_end_adjustments 0045_provisions 0047_inventory_closing 0049_payroll 0058_corporate_tax_posting 0060_equity_operations 0062_loans 0064_grants 0072_temporary_companies   →   la vigente es la de 0072_temporary_companies
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.delete_company_step(p_company uuid, p_batch integer DEFAULT 5000)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
begin
  if not exists (select 1 from erp.company_users
                 where company_id = p_company and user_id = auth.uid() and role = 'admin') then
    raise exception 'Only the company admin can delete it';
  end if;
  return erp.purge_company_step(p_company, p_batch);
end $function$
;
