-- =====================================================================
-- erp.cancel_payment · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0035_payments   →   la vigente es la de 0035_payments
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.cancel_payment(p_payment uuid, p_date date DEFAULT NULL::date, p_reason text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare
  v_p   erp.payments;
  v_no  int;
begin
  select * into v_p from erp.payments where id = p_payment;
  if not found or not erp.can_write(v_p.company_id) then raise exception 'Payment not found (or no permission)'; end if;
  if v_p.cancel_entry_id is not null then raise exception 'This payment is already cancelled'; end if;

  if v_p.linked then
    delete from erp.payments where id = v_p.id;   -- el asiento manual se queda como estaba
    return null;
  end if;

  perform set_config('erp.payment_engine', 'on', true);
  v_no := erp.reverse_entry(v_p.entry_id, coalesce(p_date, v_p.payment_date), coalesce(nullif(btrim(p_reason), ''), 'Pago anulado'));
  perform set_config('erp.payment_engine', 'off', true);
  update erp.payments set cancel_entry_id = (select reversed_by from erp.journal_entries where id = v_p.entry_id)
  where id = v_p.id;
  return v_no;
end $function$
;
