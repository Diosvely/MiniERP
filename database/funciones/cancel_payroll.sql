-- =====================================================================
-- erp.cancel_payroll · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0049_payroll   →   la vigente es la de 0049_payroll
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.cancel_payroll(p_run uuid, p_date date DEFAULT NULL::date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare r erp.payroll_runs; v_no int;
begin
  select * into r from erp.payroll_runs where id = p_run;
  if not found then raise exception 'Payroll not found'; end if;
  if not erp.can_write(r.company_id) then raise exception 'No permission to register payroll in this company'; end if;
  if r.status <> 'posted' then raise exception 'This payroll is already cancelled'; end if;
  if r.ss_payment_entry_id is not null then
    v_no := erp.adjust_reverse(r.ss_payment_entry_id, p_date, 'Pago de seguros sociales deshecho');
    update erp.payroll_runs set ss_payment_entry_id = null where id = r.id;
  elsif r.net_payment_entry_id is not null then
    v_no := erp.adjust_reverse(r.net_payment_entry_id, p_date, 'Pago de la nómina deshecho');
    update erp.payroll_runs set net_payment_entry_id = null where id = r.id;
  else
    if exists (select 1 from erp.payroll_runs x where x.company_id = r.company_id and x.period > r.period and x.status = 'posted') then
      raise exception 'Only the last payroll can be cancelled';
    end if;
    v_no := erp.adjust_reverse(r.entry_id, coalesce(p_date, r.period), 'Nómina anulada');
    update erp.payroll_runs set status = 'cancelled', cancel_entry_id = (select reversed_by from erp.journal_entries where id = r.entry_id)
    where id = r.id;
  end if;
  return v_no;
end $function$
;
