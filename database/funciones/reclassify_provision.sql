-- =====================================================================
-- erp.reclassify_provision · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0045_provisions   →   la vigente es la de 0045_provisions
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.reclassify_provision(p_provision uuid, p_date date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare v erp.provisions; v_bal numeric; v_new uuid; v_entry uuid; v_no int;
begin
  select * into v from erp.provisions where id = p_provision;
  if not found then raise exception 'Provision not found'; end if;
  if not erp.can_write(v.company_id) then raise exception 'No permission to register provisions in this company'; end if;
  if v.status <> 'active' then raise exception 'Provision % is not active', v.code; end if;
  if v.term <> 'long' then raise exception 'Provision % is already short-term', v.code; end if;
  if p_date is null then raise exception 'The date is required'; end if;
  v_bal := erp.provision_balance(v.id);
  if v_bal <= 0 then raise exception 'Provision % has no balance to reclassify', v.code; end if;
  v_new := erp.provision_account(v.company_id, v.kind, 'short');
  v_entry := erp.provision_post(v.company_id, p_date, 'Reclasificación a corto plazo de la provisión ' || v.code, jsonb_build_array(
    jsonb_build_object('account_id', v.provision_account_id, 'debit', v_bal, 'text', 'Reclasificación a corto plazo'),
    jsonb_build_object('account_id', v_new, 'credit', v_bal, 'text', 'Reclasificación a corto plazo')));
  v_no := erp.provision_add_movement(v, 'reclass', p_date, v_bal, v_bal, v_entry, null, v.provision_account_id);
  update erp.provisions set term = 'short', provision_account_id = v_new where id = v.id;
  return v_no;
end $function$
;
