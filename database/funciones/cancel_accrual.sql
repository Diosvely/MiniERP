-- =====================================================================
-- erp.cancel_accrual · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0043_year_end_adjustments   →   la vigente es la de 0043_year_end_adjustments
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.cancel_accrual(p_accrual uuid, p_date date DEFAULT NULL::date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare a erp.accruals; v_no int;
begin
  select * into a from erp.accruals where id = p_accrual;
  if not found then raise exception 'Accrual not found'; end if;
  if not erp.can_write(a.company_id) then raise exception 'No permission to register accruals in this company'; end if;
  if a.status = 'cancelled' then raise exception 'Accrual % is already cancelled', a.code; end if;
  if a.status = 'reversed' then
    v_no := erp.adjust_reverse(a.reversal_entry_id, coalesce(p_date, a.reversal_date), 'Reversión deshecha');
    update erp.accruals set status = 'active', reversal_date = null, reversal_entry_id = null where id = a.id;
  else
    v_no := erp.adjust_reverse(a.entry_id, coalesce(p_date, a.cutoff_date), 'Periodificación anulada');
    update erp.accruals set status = 'cancelled', cancel_entry_id = (select reversed_by from erp.journal_entries where id = a.entry_id)
    where id = a.id;
  end if;
  return v_no;
end $function$
;
