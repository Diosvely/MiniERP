-- =====================================================================
-- erp.cancel_provision_movement · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0045_provisions   →   la vigente es la de 0045_provisions
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.cancel_provision_movement(p_provision uuid, p_date date DEFAULT NULL::date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare v erp.provisions; m erp.provision_movements; v_no int;
begin
  select * into v from erp.provisions where id = p_provision;
  if not found then raise exception 'Provision not found'; end if;
  if not erp.can_write(v.company_id) then raise exception 'No permission to register provisions in this company'; end if;
  if v.status = 'cancelled' then raise exception 'Provision % is already cancelled', v.code; end if;
  select * into m from erp.provision_movements where provision_id = v.id order by seq desc limit 1;
  v_no := erp.adjust_reverse(m.entry_id, coalesce(p_date, m.movement_date), 'Movimiento de provisión deshecho');
  delete from erp.provision_movements where id = m.id;
  if m.kind = 'allocation' then
    update erp.provisions set status = 'cancelled' where id = v.id;
  elsif m.kind = 'application' then
    update erp.provisions set status = 'active' where id = v.id;
  elsif m.kind = 'reclass' then
    update erp.provisions set term = 'long', provision_account_id = m.account_before where id = v.id;
  end if;
  return v_no;
end $function$
;
