-- =====================================================================
-- erp.cancel_inventory · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0047_inventory_closing   →   la vigente es la de 0047_inventory_closing
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.cancel_inventory(p_count uuid, p_date date DEFAULT NULL::date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare c erp.inventory_counts; v_no int;
begin
  select * into c from erp.inventory_counts where id = p_count;
  if not found then raise exception 'Inventory count not found'; end if;
  if not erp.can_write(c.company_id) then raise exception 'No permission to register inventories in this company'; end if;
  if c.status <> 'posted' then raise exception 'This inventory is already cancelled'; end if;
  v_no := erp.adjust_reverse(c.entry_id, coalesce(p_date, c.count_date), 'Inventario deshecho');
  update erp.inventory_counts set status = 'cancelled', cancel_entry_id = (select reversed_by from erp.journal_entries where id = c.entry_id)
  where id = c.id;
  return v_no;
end $function$
;
