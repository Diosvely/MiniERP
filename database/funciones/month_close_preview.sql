-- =====================================================================
-- erp.month_close_preview · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0069_monthly_accounting   →   la vigente es la de 0069_monthly_accounting
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.month_close_preview(p_company uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare v_p erp.accounting_periods; v_w jsonb := '[]'::jsonb; v_n int; v_q int; v_tax text;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  v_p := erp.work_period(p_company);
  if v_p.fiscal_year_id is null then raise exception 'There is no open month'; end if;
  -- borradores del mes: no se podrán contabilizar con el mes cerrado
  select count(*) into v_n from erp.journal_entries j
  where j.company_id = p_company and j.status = 'draft' and j.posting_date between v_p.starting_date and v_p.ending_date;
  if v_n > 0 then v_w := v_w || jsonb_build_object('code', 'drafts', 'count', v_n); end if;
  -- la nómina del mes, si hay empleados de alta
  if exists (select 1 from erp.employees m where m.company_id = p_company and m.hire_date <= v_p.ending_date
             and (m.end_date is null or m.end_date >= v_p.starting_date))
     and not exists (select 1 from erp.payroll_runs r where r.company_id = p_company and r.period = v_p.ending_date and r.status = 'posted') then
    v_w := v_w || jsonb_build_object('code', 'payroll');
  end if;
  -- al cerrar un trimestre, su liquidación del IVA / IGIC
  if v_p.period_no in (3, 6, 9, 12) then
    v_q := v_p.period_no / 3;
    select case when tax_territory = 'canary_islands' then 'IGIC' else 'VAT' end into v_tax from erp.companies where id = p_company;
    if exists (select 1 from erp.tax_setup s where s.company_id = p_company)
       and not exists (select 1 from erp.tax_settlements t where t.company_id = p_company and t.year = extract(year from v_p.starting_date)
                       and t.quarter = v_q and t.status = 'posted') then
      v_w := v_w || jsonb_build_object('code', 'settlement', 'quarter', v_q, 'tax', v_tax);
    end if;
  end if;
  return jsonb_build_object('year', extract(year from v_p.starting_date)::int, 'month', v_p.period_no,
    'from', v_p.starting_date, 'to', v_p.ending_date, 'december', v_p.period_no = 12,
    'entries', (select count(*) from erp.journal_entries j where j.company_id = p_company and j.status = 'posted'
                and j.posting_date between v_p.starting_date and v_p.ending_date),
    'warnings', v_w);
end $function$
;
