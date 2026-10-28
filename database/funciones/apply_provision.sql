-- =====================================================================
-- erp.apply_provision · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0045_provisions   →   la vigente es la de 0045_provisions
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.apply_provision(p jsonb)
 RETURNS TABLE(entry_no integer, difference numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  v       erp.provisions;
  v_date  date := (p->>'application_date')::date;
  v_paid  numeric := round((p->>'paid')::numeric, 2);
  v_cash  erp.gl_accounts;
  v_bal   numeric;
  v_entry uuid;
begin
  select * into v from erp.provisions where id = (p->>'provision_id')::uuid;
  if not found then raise exception 'Provision not found'; end if;
  if not erp.can_write(v.company_id) then raise exception 'No permission to register provisions in this company'; end if;
  if v.status <> 'active' then raise exception 'Provision % is not active', v.code; end if;
  if v_date is null then raise exception 'The application date is required'; end if;
  if v_paid is null or v_paid < 0 then raise exception 'The amount paid cannot be negative'; end if;
  select * into v_cash from erp.gl_accounts
  where company_id = v.company_id and account_no = p->>'cash_account_no' and account_type = 'posting';
  if v_paid > 0 and (not found or left(v_cash.account_no, 2) <> '57') then raise exception 'Choose a cash or bank account (57)'; end if;
  v_bal := erp.provision_balance(v.id);
  v_entry := erp.provision_post(v.company_id, v_date, 'Aplicación de la provisión ' || v.code || ' · ' || v.description, jsonb_build_array(
    jsonb_build_object('account_id', v.provision_account_id, 'debit', v_bal, 'text', 'Aplicación de la provisión'),
    jsonb_build_object('account_id', v.expense_account_id, 'debit', greatest(v_paid - v_bal, 0), 'text', 'Pagado de más sobre lo provisionado'),
    jsonb_build_object('account_id', v_cash.id, 'credit', v_paid, 'text', 'Pago'),
    jsonb_build_object('account_id', v.excess_account_id, 'credit', greatest(v_bal - v_paid, 0), 'text', 'Exceso de provisión')));
  entry_no := erp.provision_add_movement(v, 'application', v_date, v_bal, 0, v_entry, v_paid);
  update erp.provisions set status = 'applied' where id = v.id;
  difference := v_paid - v_bal;
  return next;
end $function$
;
