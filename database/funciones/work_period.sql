-- =====================================================================
-- erp.work_period · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0069_monthly_accounting   →   la vigente es la de 0069_monthly_accounting
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.work_period(p_company uuid)
 RETURNS erp.accounting_periods
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select p.* from erp.accounting_periods p
  join erp.fiscal_years fy on fy.id = p.fiscal_year_id and fy.company_id = p_company and fy.status = 'open'
  join erp.companies c on c.id = p_company
  where p.status = 'open' and p.ending_date >= coalesce(c.start_date, '0001-01-01'::date)
  order by p.starting_date
  limit 1;
$function$
;
