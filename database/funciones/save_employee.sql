-- =====================================================================
-- erp.save_employee · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0049_payroll   →   la vigente es la de 0049_payroll
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.save_employee(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare v_company uuid := (p->>'company_id')::uuid; v_id uuid := (p->>'id')::uuid; v_code text;
begin
  if not erp.can_write(v_company) then raise exception 'No permission to register payroll in this company'; end if;
  if coalesce(btrim(p->>'name'), '') = '' then raise exception 'The employee needs a name'; end if;
  if (p->>'hire_date') is null then raise exception 'The hire date is required'; end if;
  if coalesce((p->>'monthly_salary')::numeric, 0) <= 0 then raise exception 'The monthly salary must be greater than zero'; end if;
  if v_id is null then
    select 'EMP-' || lpad((count(*) + 1)::text, 4, '0') into v_code from erp.employees where company_id = v_company;
    insert into erp.employees (company_id, code, name, contract_type, hire_date, end_date, monthly_salary, extra_payments, extra_prorated, irpf_pct, at_ep_pct)
    values (v_company, v_code, btrim(p->>'name'), coalesce(p->>'contract_type', 'indefinite'), (p->>'hire_date')::date, (p->>'end_date')::date,
            round((p->>'monthly_salary')::numeric, 2), coalesce((p->>'extra_payments')::int, 2), coalesce((p->>'extra_prorated')::boolean, false),
            coalesce((p->>'irpf_pct')::numeric, 0), coalesce((p->>'at_ep_pct')::numeric, 1.00))
    returning id into v_id;
  else
    update erp.employees set name = btrim(p->>'name'), contract_type = coalesce(p->>'contract_type', contract_type),
      end_date = (p->>'end_date')::date, monthly_salary = round((p->>'monthly_salary')::numeric, 2),
      extra_payments = coalesce((p->>'extra_payments')::int, extra_payments), extra_prorated = coalesce((p->>'extra_prorated')::boolean, extra_prorated),
      irpf_pct = coalesce((p->>'irpf_pct')::numeric, irpf_pct), at_ep_pct = coalesce((p->>'at_ep_pct')::numeric, at_ep_pct)
    where id = v_id and company_id = v_company;
    if not found then raise exception 'Employee not found'; end if;
  end if;
  return v_id;
end $function$
;
