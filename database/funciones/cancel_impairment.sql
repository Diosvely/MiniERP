-- =====================================================================
-- erp.cancel_impairment · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0043_year_end_adjustments   →   la vigente es la de 0043_year_end_adjustments
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.cancel_impairment(p_impairment uuid, p_date date DEFAULT NULL::date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare i erp.receivable_impairments; v_no int;
begin
  select * into i from erp.receivable_impairments where id = p_impairment;
  if not found then raise exception 'Impairment not found'; end if;
  if not erp.can_write(i.company_id) then raise exception 'No permission to register impairments in this company'; end if;
  if i.status = 'cancelled' then raise exception 'Impairment % is already cancelled', i.code; end if;
  if i.status = 'written_off' then raise exception 'Impairment % was applied to a write-off: cancel the write-off first', i.code; end if;
  if i.status = 'reversed' then
    if exists (select 1 from erp.receivable_impairments x where x.invoice_id = i.invoice_id and x.status = 'active' and x.id <> i.id)
       or (i.method = 'global' and exists (select 1 from erp.receivable_impairments x
                                           where x.company_id = i.company_id and x.method = 'global' and x.status = 'active')) then
      raise exception 'There is a newer active impairment: cancel it first';
    end if;
    v_no := erp.adjust_reverse(i.end_entry_id, coalesce(p_date, i.end_date), 'Reversión deshecha');
    update erp.receivable_impairments set status = 'active', end_date = null, end_entry_id = null where id = i.id;
  else
    v_no := erp.adjust_reverse(i.entry_id, coalesce(p_date, i.impair_date), 'Deterioro anulado');
    update erp.receivable_impairments set status = 'cancelled', cancel_entry_id = (select reversed_by from erp.journal_entries where id = i.entry_id)
    where id = i.id;
  end if;
  return v_no;
end $function$
;
