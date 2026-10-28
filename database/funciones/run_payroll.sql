-- =====================================================================
-- erp.run_payroll · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0049_payroll   →   la vigente es la de 0049_payroll
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.run_payroll(p jsonb)
 RETURNS TABLE(run_id uuid, entry_no integer, employees integer, gross numeric, net numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  v_company uuid := (p->>'company_id')::uuid;
  v_period  date := (date_trunc('month', (p->>'period')::date) + interval '1 month - 1 day')::date;
  v_entry   uuid; v_run uuid; e erp.employees; c jsonb; v_n int := 0; v_line int := 0; v_gross numeric := 0; v_net numeric := 0;
  a640 uuid; a642 uuid; a476 uuid; a4751 uuid; a465 uuid; v_no int;
begin
  if not erp.can_write(v_company) then raise exception 'No permission to register payroll in this company'; end if;
  if (p->>'period') is null then raise exception 'The month is required'; end if;
  if exists (select 1 from erp.payroll_runs r where r.company_id = v_company and r.period = v_period and r.status = 'posted') then
    raise exception 'The payroll of % is already posted', to_char(v_period, 'MM/YYYY');
  end if;
  if exists (select 1 from erp.payroll_runs r where r.company_id = v_company and r.period > v_period and r.status = 'posted') then
    raise exception 'There is a later payroll: post the months in order';
  end if;
  a640 := erp.adjust_account(v_company, '640', 'Sueldos y salarios');
  a642 := erp.adjust_account(v_company, '642', 'Seguridad Social a cargo de la empresa');
  a476 := erp.adjust_account(v_company, '476', 'Organismos de la Seguridad Social, acreedores');
  a4751 := erp.adjust_account(v_company, '4751', 'Hacienda Pública, acreedora por retenciones practicadas');
  a465 := erp.adjust_account(v_company, '465', 'Remuneraciones pendientes de pago');
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (v_company, erp.adjust_fiscal_year(v_company, v_period), v_period, 'Nómina de ' || to_char(v_period, 'MM/YYYY'))
  returning id into v_entry;
  insert into erp.payroll_runs (company_id, period, entry_id) values (v_company, v_period, v_entry) returning id into v_run;

  for e in select * from erp.employees x where x.company_id = v_company and x.hire_date <= v_period
           and (x.end_date is null or x.end_date >= date_trunc('month', v_period)) order by x.code loop
    c := erp.payslip_calc(e.id, v_period);
    insert into erp.payslips (run_id, employee_id, company_id, salary, extra_accrual, extra_paid, ss_base, ss_employee, ss_employer,
                              ss_detail, irpf_pct, irpf, net, warnings)
    values (v_run, e.id, v_company, (c->>'salary')::numeric, (c->>'extra_accrual')::numeric, (c->>'extra_paid')::numeric,
            (c->>'ss_base')::numeric, (c->>'ss_employee')::numeric, (c->>'ss_employer')::numeric, c->'ss_detail',
            (c->>'irpf_pct')::numeric, (c->>'irpf')::numeric, (c->>'net')::numeric, c->'warnings');
    insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description)
    select v_entry, v_company, v_line + row_number() over (), x.acc, x.d, x.h, e.code || ' · ' || e.name || ' · ' || x.txt
    from (values
      (1, a640, (c->>'salary')::numeric, 0::numeric, 'salario'),
      (2, a640, (c->>'extra_accrual')::numeric, 0::numeric, 'paga extra devengada'),
      (3, a465, (c->>'extra_paid')::numeric, 0::numeric, 'paga extra que se paga'),
      (4, a642, (c->>'ss_employer')::numeric, 0::numeric, 'Seguridad Social a cargo de la empresa'),
      (5, a476, 0::numeric, (c->>'ss_employer')::numeric + (c->>'ss_employee')::numeric, 'cuotas de la Seguridad Social'),
      (6, a4751, 0::numeric, (c->>'irpf')::numeric, 'retención del IRPF'),
      (7, a465, 0::numeric, (c->>'net')::numeric, 'líquido a pagar'),
      (8, a465, 0::numeric, (c->>'extra_accrual')::numeric, 'paga extra devengada')) as x(k, acc, d, h, txt)
    where x.d <> 0 or x.h <> 0 order by x.k;
    get diagnostics v_line = row_count;
    v_line := (select max(line_no) from erp.journal_lines where entry_id = v_entry);
    v_n := v_n + 1; v_gross := v_gross + (c->>'salary')::numeric + (c->>'extra_accrual')::numeric; v_net := v_net + (c->>'net')::numeric;
  end loop;
  if v_n = 0 then raise exception 'There are no employees in % (check the hire dates)', to_char(v_period, 'MM/YYYY'); end if;
  v_no := erp.adjust_finish(v_entry);
  run_id := v_run; entry_no := v_no; employees := v_n; gross := v_gross; net := v_net;
  return next;
end $function$
;
