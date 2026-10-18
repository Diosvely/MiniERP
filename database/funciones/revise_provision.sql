-- =====================================================================
-- erp.revise_provision · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0045_provisions   →   la vigente es la de 0045_provisions
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.revise_provision(p jsonb)
 RETURNS TABLE(entry_no integer, difference numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare
  v       erp.provisions;
  v_date  date := (p->>'review_date')::date;
  v_new   numeric := round((p->>'new_amount')::numeric, 2);
  v_old   numeric;
  v_entry uuid;
  v_lines jsonb;
begin
  select * into v from erp.provisions where id = (p->>'provision_id')::uuid;
  if not found then raise exception 'Provision not found'; end if;
  if not erp.can_write(v.company_id) then raise exception 'No permission to register provisions in this company'; end if;
  if v.status <> 'active' then raise exception 'Provision % is not active', v.code; end if;
  if v_date is null then raise exception 'The review date is required'; end if;
  if v_new is null or v_new < 0 then raise exception 'The new estimate cannot be negative'; end if;
  v_old := erp.provision_balance(v.id);
  if v.kind = 'commercial' then
    -- PGC (499): se abona la del año por la dotación (6959) y se carga la anterior por el exceso (7954)
    v_lines := jsonb_build_array(
      jsonb_build_object('account_id', v.provision_account_id, 'debit', v_old, 'text', 'Exceso de la estimación anterior'),
      jsonb_build_object('account_id', v.excess_account_id, 'credit', v_old, 'text', 'Exceso de la estimación anterior'),
      jsonb_build_object('account_id', v.expense_account_id, 'debit', v_new, 'text', 'Dotación del ejercicio'),
      jsonb_build_object('account_id', v.provision_account_id, 'credit', v_new, 'text', 'Dotación del ejercicio'));
  elsif v_new = v_old then
    raise exception 'The new estimate is the same as the current one (%)', v_old;
  elsif v_new > v_old then
    v_lines := jsonb_build_array(
      jsonb_build_object('account_id', v.expense_account_id, 'debit', v_new - v_old, 'text', 'Aumento de la estimación'),
      jsonb_build_object('account_id', v.provision_account_id, 'credit', v_new - v_old, 'text', 'Aumento de la estimación'));
  else
    v_lines := jsonb_build_array(
      jsonb_build_object('account_id', v.provision_account_id, 'debit', v_old - v_new, 'text', 'Exceso de provisión'),
      jsonb_build_object('account_id', v.excess_account_id, 'credit', v_old - v_new, 'text', 'Exceso de provisión'));
  end if;
  if v.kind = 'commercial' and v_old = 0 and v_new = 0 then raise exception 'The new estimate is the same as the current one (%)', v_old; end if;
  v_entry := erp.provision_post(v.company_id, v_date, 'Revisión de la provisión ' || v.code || ' · ' || v.description, v_lines);
  entry_no := erp.provision_add_movement(v, 'revision', v_date, v_old, v_new, v_entry);
  difference := v_new - v_old;
  return next;
end $function$
;
