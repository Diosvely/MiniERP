-- =====================================================================
-- erp.payslip_calc · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0049_payroll   →   la vigente es la de 0049_payroll
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.payslip_calc(p_employee uuid, p_period date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  e        erp.employees;
  lim      erp.ss_limits;
  r        record;
  v_year   int := extract(year from p_period)::int;
  v_month  int := extract(month from p_period)::int;
  v_prorr  numeric;     -- prorrata mensual de las pagas extra
  v_salary numeric;     -- lo que se paga este mes por salario
  v_base   numeric;     -- base de cotización
  v_rem    numeric;     -- remuneración total del mes (para la solidaridad)
  v_acc    numeric := 0;
  v_paid   numeric := 0;
  v_prev   numeric;     -- lo devengado de la paga desde el último pago
  v_n      int;         -- meses del periodo de devengo de esta paga
  v_ee     numeric := 0; v_er numeric := 0; v_det jsonb := '[]'; v_amt_e numeric; v_amt_r numeric; v_b numeric;
  v_irpf   numeric;
  v_warn   jsonb := '[]';
  v_pay_month boolean;
begin
  select * into e from erp.employees where id = p_employee;
  select * into lim from erp.ss_limits where year = v_year;
  if lim.year is null then raise exception 'There are no contribution rates for %: they are published each year (Orden de cotización)', v_year; end if;

  v_prorr := round(e.monthly_salary * e.extra_payments / 12, 2);
  -- meses de pago de las pagas extra: junio y diciembre (2), o repartidos si son más (3: abril, agosto y diciembre…)
  v_pay_month := e.extra_payments > 0 and v_month % (12 / greatest(e.extra_payments, 1)) = 0;
  if e.extra_prorated then
    v_salary := e.monthly_salary + v_prorr;
  else
    v_salary := e.monthly_salary;
    if e.extra_payments > 0 then
      -- lo devengado desde el último mes de paga (en las nóminas ya contabilizadas)
      select coalesce(sum(s.extra_accrual), 0), count(*) into v_prev, v_n
      from erp.payslips s join erp.payroll_runs pr on pr.id = s.run_id
      where s.employee_id = e.id and pr.status = 'posted' and pr.period < p_period
        and pr.period > (select coalesce(max(pr2.period), '1900-01-01') from erp.payslips s2 join erp.payroll_runs pr2 on pr2.id = s2.run_id
                         where s2.employee_id = e.id and pr2.status = 'posted' and pr2.period < p_period and s2.extra_paid > 0);
      v_acc := v_prorr;
      if v_pay_month then
        -- el mes de paga cuadra el redondeo: la paga es exactamente la parte de los meses devengados
        v_acc := round(e.monthly_salary * e.extra_payments / 12 * (v_n + 1), 2) - v_prev;
        v_paid := v_prev + v_acc;
      end if;
    end if;
  end if;

  -- Base de cotización: salario + prorrata de las pagas extra, con el tope máximo
  v_rem := e.monthly_salary + v_prorr;
  v_base := least(v_rem, lim.max_base);
  if e.hire_date > date_trunc('month', p_period)::date or (e.end_date is not null and e.end_date < p_period) then
    v_warn := v_warn || jsonb_build_object('code', 'partial_month');   -- el ERP liquida el mes entero: prorratea a mano
  end if;
  if v_base < lim.min_base then v_warn := v_warn || jsonb_build_object('code', 'below_min_base', 'min_base', lim.min_base); end if;

  for r in select * from erp.ss_rates s where s.year = v_year
           and s.concept <> case e.contract_type when 'indefinite' then 'unemployment_temporary' else 'unemployment_indefinite' end
           order by s.sort loop
    v_b := case r.concept
      when 'solidarity_1' then greatest(least(v_rem, lim.solidarity_1) - lim.max_base, 0)
      when 'solidarity_2' then greatest(least(v_rem, lim.solidarity_2) - lim.solidarity_1, 0)
      when 'solidarity_3' then greatest(v_rem - lim.solidarity_2, 0)
      else v_base end;
    if v_b = 0 then continue; end if;
    v_amt_r := round(v_b * r.employer_pct / 100, 2); v_amt_e := round(v_b * r.employee_pct / 100, 2);
    v_er := v_er + v_amt_r; v_ee := v_ee + v_amt_e;
    v_det := v_det || jsonb_build_object('concept', r.concept, 'name', r.name, 'name_en', r.name_en, 'base', v_b,
                                         'employer_pct', r.employer_pct, 'employee_pct', r.employee_pct, 'employer', v_amt_r, 'employee', v_amt_e);
  end loop;
  -- AT / EP: solo la empresa (tarifa de primas)
  v_amt_r := round(v_base * e.at_ep_pct / 100, 2); v_er := v_er + v_amt_r;
  v_det := v_det || jsonb_build_object('concept', 'at_ep', 'name', 'Accidentes de trabajo y enfermedades profesionales', 'name_en', 'Work accidents and occupational diseases',
                                       'base', v_base, 'employer_pct', e.at_ep_pct, 'employee_pct', 0, 'employer', v_amt_r, 'employee', 0);

  v_irpf := round((v_salary + v_paid) * e.irpf_pct / 100, 2);
  return jsonb_build_object('salary', v_salary, 'extra_accrual', v_acc, 'extra_paid', v_paid, 'ss_base', v_base,
    'ss_employee', v_ee, 'ss_employer', v_er, 'ss_detail', v_det, 'irpf_pct', e.irpf_pct, 'irpf', v_irpf,
    'net', v_salary + v_paid - v_irpf - v_ee, 'warnings', v_warn);
end $function$
;
