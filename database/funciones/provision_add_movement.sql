-- =====================================================================
-- erp.provision_add_movement · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0045_provisions   →   la vigente es la de 0045_provisions
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.provision_add_movement(p erp.provisions, p_kind text, p_date date, p_before numeric, p_after numeric, p_entry uuid, p_paid numeric DEFAULT NULL::numeric, p_account_before uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
begin
  if exists (select 1 from erp.provision_movements m where m.provision_id = p.id and m.movement_date > p_date) then
    raise exception 'Provision % already has a movement after %', p.code, p_date;
  end if;
  insert into erp.provision_movements (provision_id, company_id, seq, kind, movement_date, balance_before, balance_after, paid, account_before, entry_id)
  values (p.id, p.company_id, coalesce((select max(seq) from erp.provision_movements where provision_id = p.id), 0) + 1,
          p_kind, p_date, p_before, p_after, p_paid, p_account_before, p_entry);
  return erp.adjust_finish(p_entry);
end $function$
;
