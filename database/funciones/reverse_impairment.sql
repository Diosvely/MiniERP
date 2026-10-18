-- =====================================================================
-- erp.reverse_impairment · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0043_year_end_adjustments   →   la vigente es la de 0043_year_end_adjustments
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.reverse_impairment(p_impairment uuid, p_date date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare i erp.receivable_impairments; v_entry uuid; v_no int;
begin
  select * into i from erp.receivable_impairments where id = p_impairment;
  if not found then raise exception 'Impairment not found'; end if;
  if not erp.can_write(i.company_id) then raise exception 'No permission to register impairments in this company'; end if;
  if i.status <> 'active' then raise exception 'Impairment % is not active', i.code; end if;
  if p_date is null or p_date < i.impair_date then raise exception 'The reversal date cannot be earlier than the impairment (%)', i.impair_date; end if;
  v_entry := erp.adjust_post(i.company_id, p_date, 'Reversión del deterioro ' || i.code, null,
    erp.adjust_account(i.company_id, '490', 'Deterioro de valor de créditos por operaciones comerciales'),
    erp.adjust_account(i.company_id, '794', 'Reversión del deterioro de créditos por operaciones comerciales'), i.amount);
  update erp.receivable_impairments set status = 'reversed', end_date = p_date, end_entry_id = v_entry where id = i.id;
  v_no := erp.adjust_finish(v_entry);
  return v_no;
end $function$
;
