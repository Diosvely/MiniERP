-- =====================================================================
-- erp.adjust_fiscal_year · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0043_year_end_adjustments   →   la vigente es la de 0043_year_end_adjustments
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.adjust_fiscal_year(p_company uuid, p_date date)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE
 SET jit TO 'off'
AS $function$
declare v uuid;
begin
  select id into v from erp.fiscal_years where company_id = p_company and p_date between starting_date and ending_date;
  if v is null then raise exception 'No fiscal year for date %: create it first', p_date; end if;
  return v;
end $function$
;
