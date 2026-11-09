-- =====================================================================
-- erp.corporate_tax_period · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0091_corporate_tax_fixes   →   la vigente es la de 0091_corporate_tax_fixes
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.corporate_tax_period(p_return uuid, p_start date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare r erp.corporate_tax_returns; v_fy erp.fiscal_years;
begin
  r := erp.corporate_tax_draft(p_return);
  select * into v_fy from erp.fiscal_years where id = r.fiscal_year_id;
  if p_start is not null and (p_start < v_fy.starting_date or p_start > v_fy.ending_date) then
    raise exception 'The tax period must start within the fiscal year (% to %)', v_fy.starting_date, v_fy.ending_date;
  end if;
  update erp.corporate_tax_returns set period_start = nullif(p_start, v_fy.starting_date) where id = p_return;
end $function$
;
