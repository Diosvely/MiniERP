-- =====================================================================
-- erp.work_month · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0069_monthly_accounting   →   la vigente es la de 0069_monthly_accounting
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.work_month(p_company uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare v_co erp.companies; v_p erp.accounting_periods; v_last date;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  select * into v_co from erp.companies where id = p_company;
  v_p := erp.work_period(p_company);
  if v_p.fiscal_year_id is null then
    return jsonb_build_object('monthly', v_co.monthly, 'start_date', v_co.start_date, 'year', null);
  end if;
  select max(j.posting_date) into v_last from erp.journal_entries j
  where j.company_id = p_company and j.status = 'posted' and j.entry_type = 'normal'
    and j.posting_date between v_p.starting_date and v_p.ending_date;
  return jsonb_build_object('monthly', v_co.monthly, 'start_date', v_co.start_date,
    'year', extract(year from v_p.starting_date)::int, 'month', v_p.period_no,
    'from', greatest(v_p.starting_date, coalesce(v_co.start_date, v_p.starting_date)), 'to', v_p.ending_date,
    'last_entry_date', v_last,
    -- la fecha que proponen los formularios: la del último asiento del mes o, si no hay, el primer día del mes
    'work_date', coalesce(v_last, greatest(v_p.starting_date, coalesce(v_co.start_date, v_p.starting_date))),
    'december', v_p.period_no = 12);
end $function$
;
