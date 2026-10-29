-- =====================================================================
-- erp.reopen_month · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0069_monthly_accounting   →   la vigente es la de 0069_monthly_accounting
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.reopen_month(p_company uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare v_p erp.accounting_periods; v_prev erp.accounting_periods; v_start date;
begin
  if not erp.is_admin(p_company) then raise exception 'No permission: only the company admin can reopen a month'; end if;
  if not exists (select 1 from erp.companies where id = p_company and monthly) then
    raise exception 'This company does not use monthly accounting';
  end if;
  perform pg_advisory_xact_lock(hashtext('month/' || p_company));
  v_p := erp.work_period(p_company);
  if v_p.fiscal_year_id is null then raise exception 'There is no open month'; end if;
  select start_date into v_start from erp.companies where id = p_company;
  select * into v_prev from erp.accounting_periods
  where fiscal_year_id = v_p.fiscal_year_id and period_no = v_p.period_no - 1 and ending_date >= coalesce(v_start, '0001-01-01'::date);
  if v_prev.fiscal_year_id is null then
    if v_p.period_no = 1 and exists (select 1 from erp.fiscal_years fy where fy.company_id = p_company
                                     and fy.year = extract(year from v_p.starting_date)::int - 1 and fy.status = 'closed') then
      raise exception 'The previous month belongs to a closed fiscal year: reopen the fiscal year first';
    end if;
    raise exception 'There is no closed month to reopen';
  end if;
  update erp.accounting_periods set status = 'open' where fiscal_year_id = v_prev.fiscal_year_id and period_no = v_prev.period_no;
  return erp.work_month(p_company);
end $function$
;
