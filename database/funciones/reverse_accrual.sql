-- =====================================================================
-- erp.reverse_accrual · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0043_year_end_adjustments   →   la vigente es la de 0043_year_end_adjustments
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.reverse_accrual(p_accrual uuid, p_date date DEFAULT NULL::date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare a erp.accruals; v_date date; v_entry uuid; v_no int;
begin
  select * into a from erp.accruals where id = p_accrual;
  if not found then raise exception 'Accrual not found'; end if;
  if not erp.can_write(a.company_id) then raise exception 'No permission to register accruals in this company'; end if;
  if a.status <> 'active' then raise exception 'Accrual % is not pending reversal', a.code; end if;
  v_date := coalesce(p_date, a.cutoff_date + 1);
  if v_date <= a.cutoff_date then raise exception 'The reversal must be after the cut-off date (%)', a.cutoff_date; end if;
  v_entry := case
    when a.kind in ('prepaid_expense', 'accrued_income')
      then erp.adjust_post(a.company_id, v_date, 'Reversión de la periodificación ' || a.code || ' · ' || a.description, null, a.pl_account_id, a.balance_account_id, a.amount)
    else erp.adjust_post(a.company_id, v_date, 'Reversión de la periodificación ' || a.code || ' · ' || a.description, null, a.balance_account_id, a.pl_account_id, a.amount) end;
  update erp.accruals set status = 'reversed', reversal_date = v_date, reversal_entry_id = v_entry where id = a.id;
  v_no := erp.adjust_finish(v_entry);
  return v_no;
end $function$
;
