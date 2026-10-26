-- =====================================================================
-- erp.close_month · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0069_monthly_accounting   →   la vigente es la de 0069_monthly_accounting
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.close_month(p_company uuid, p_accept_warnings boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare v_p erp.accounting_periods; v_prev jsonb;
begin
  if not erp.can_write(p_company) then raise exception 'No permission to close months in this company'; end if;
  if not exists (select 1 from erp.companies where id = p_company and monthly) then
    raise exception 'This company does not use monthly accounting';
  end if;
  perform pg_advisory_xact_lock(hashtext('month/' || p_company));
  v_p := erp.work_period(p_company);
  if v_p.fiscal_year_id is null then raise exception 'There is no open month'; end if;
  if v_p.period_no = 12 then raise exception 'December is closed with the year-end closing'; end if;
  v_prev := erp.month_close_preview(p_company);
  if jsonb_array_length(v_prev->'warnings') > 0 and not coalesce(p_accept_warnings, false) then
    raise exception 'Review and accept the warnings before closing the month';
  end if;
  update erp.accounting_periods set status = 'closed' where fiscal_year_id = v_p.fiscal_year_id and period_no = v_p.period_no;
  return jsonb_build_object('closed', jsonb_build_object('year', extract(year from v_p.starting_date)::int, 'month', v_p.period_no),
                            'warnings', v_prev->'warnings', 'work_month', erp.work_month(p_company));
end $function$
;
