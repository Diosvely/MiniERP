-- =====================================================================
-- erp.reverse_accruals · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0043_year_end_adjustments   →   la vigente es la de 0043_year_end_adjustments
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.reverse_accruals(p_company uuid, p_date date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare r record; v_n int := 0;
begin
  if not erp.can_write(p_company) then raise exception 'No permission to register accruals in this company'; end if;
  for r in select id from erp.accruals where company_id = p_company and status = 'active' and cutoff_date < p_date order by code loop
    perform erp.reverse_accrual(r.id, p_date);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $function$
;
