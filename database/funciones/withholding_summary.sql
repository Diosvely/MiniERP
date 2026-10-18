-- =====================================================================
-- erp.withholding_summary · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0018_withholding_exempt 0050_payroll_integration   →   la vigente es la de 0050_payroll_integration
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.withholding_summary(p_company uuid, p_year integer, p_quarter integer)
 RETURNS TABLE(side text, form text, withholding_code text, rate_pct numeric, recipients integer, base numeric, amount numeric)
 LANGUAGE sql
 STABLE
AS $function$
  select * from (
    select r.side, case r.side when 'withheld' then r.form end as form, r.withholding_code, r.rate_pct,
           count(distinct r.partner_id)::int as recipients, sum(r.withholding_base) as base, sum(r.withholding_amount) as amount
    from erp.v_withholding_register r
    where r.company_id = p_company and r.fiscal_year = p_year and r.quarter = p_quarter
    group by r.side, r.form, r.withholding_code, r.rate_pct
    union all
    -- v0.38.0: nóminas (rendimientos del trabajo)
    select 'withheld', '111', 'payroll', null::numeric, count(distinct s.employee_id)::int, sum(s.salary + s.extra_paid), sum(s.irpf)
    from erp.payslips s
    join erp.payroll_runs pr on pr.id = s.run_id
    join erp.journal_entries je on je.id = pr.entry_id
    join erp.fiscal_years f on f.id = je.fiscal_year_id
    where pr.company_id = p_company and pr.status = 'posted' and f.year = p_year
      and extract(quarter from pr.period) = p_quarter
    having count(*) > 0
  ) x
  order by x.side desc, x.form, (x.withholding_code = 'payroll') desc, x.withholding_code;
$function$
;
