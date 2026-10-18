-- =====================================================================
-- erp.pay_payroll · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0049_payroll   →   la vigente es la de 0049_payroll
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.pay_payroll(p jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare
  r erp.payroll_runs; v_date date := (p->>'payment_date')::date; v_cash erp.gl_accounts; v_amt numeric; v_entry uuid; v_no int;
  v_what text := coalesce(p->>'what', 'net');
begin
  select * into r from erp.payroll_runs where id = (p->>'run_id')::uuid;
  if not found then raise exception 'Payroll not found'; end if;
  if not erp.can_write(r.company_id) then raise exception 'No permission to register payroll in this company'; end if;
  if r.status <> 'posted' then raise exception 'This payroll is cancelled'; end if;
  if v_what not in ('net', 'social_security') then raise exception 'Invalid payment: %', v_what; end if;
  if v_date is null or v_date < r.period - 5 then raise exception 'The payment date is required (and not before the end of the month)'; end if;
  if (v_what = 'net' and r.net_payment_entry_id is not null) or (v_what = 'social_security' and r.ss_payment_entry_id is not null) then
    raise exception 'This payment is already posted';
  end if;
  select * into v_cash from erp.gl_accounts where company_id = r.company_id and account_no = p->>'cash_account_no' and account_type = 'posting';
  if not found or left(v_cash.account_no, 2) <> '57' then raise exception 'Choose a cash or bank account (57)'; end if;
  select case v_what when 'net' then sum(s.net) else sum(s.ss_employee + s.ss_employer) end into v_amt from erp.payslips s where s.run_id = r.id;
  v_entry := erp.adjust_post(r.company_id, v_date,
    case v_what when 'net' then 'Pago de la nómina de ' else 'Pago de los seguros sociales de ' end || to_char(r.period, 'MM/YYYY'), null,
    erp.adjust_account(r.company_id, case v_what when 'net' then '465' else '476' end,
                       case v_what when 'net' then 'Remuneraciones pendientes de pago' else 'Organismos de la Seguridad Social, acreedores' end),
    v_cash.id, v_amt);
  if v_what = 'net' then update erp.payroll_runs set net_payment_entry_id = v_entry where id = r.id;
  else update erp.payroll_runs set ss_payment_entry_id = v_entry where id = r.id; end if;
  v_no := erp.adjust_finish(v_entry);
  return v_no;
end $function$
;
