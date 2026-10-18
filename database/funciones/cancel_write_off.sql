-- =====================================================================
-- erp.cancel_write_off · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0043_year_end_adjustments   →   la vigente es la de 0043_year_end_adjustments
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.cancel_write_off(p_writeoff uuid, p_date date DEFAULT NULL::date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare w erp.receivable_writeoffs; v_no int; v_rev uuid;
begin
  select * into w from erp.receivable_writeoffs where id = p_writeoff;
  if not found then raise exception 'Write-off not found'; end if;
  if not erp.can_write(w.company_id) then raise exception 'No permission to register impairments in this company'; end if;
  if w.cancel_entry_id is not null then raise exception 'This write-off is already cancelled'; end if;
  v_no := erp.adjust_reverse(w.entry_id, coalesce(p_date, w.writeoff_date), 'Insolvencia anulada');
  v_rev := (select reversed_by from erp.journal_entries where id = w.entry_id);
  update erp.payments set cancel_entry_id = v_rev where id = w.payment_id;
  update erp.receivable_writeoffs set cancel_entry_id = v_rev where id = w.id;
  if w.impairment_id is not null then
    update erp.receivable_impairments set status = 'active', end_date = null, end_entry_id = null where id = w.impairment_id;
  end if;
  return v_no;
end $function$
;
