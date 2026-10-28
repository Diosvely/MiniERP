-- =====================================================================
-- erp.create_fiscal_year · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0001_core   →   la vigente es la de 0001_core
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.create_fiscal_year(p_company uuid, p_year integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SET jit TO 'off'
AS $function$
declare
  v_id uuid;
  m    int;
begin
  insert into erp.fiscal_years (company_id, year, starting_date, ending_date)
  values (p_company, p_year, make_date(p_year, 1, 1), make_date(p_year, 12, 31))
  returning id into v_id;

  for m in 1..12 loop
    insert into erp.accounting_periods (fiscal_year_id, period_no, starting_date, ending_date)
    values (v_id, m,
            make_date(p_year, m, 1),
            (make_date(p_year, m, 1) + interval '1 month - 1 day')::date);
  end loop;
  return v_id;
end $function$
;
