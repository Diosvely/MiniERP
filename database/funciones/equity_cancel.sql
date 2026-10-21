-- =====================================================================
-- erp.equity_cancel · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0060_equity_operations   →   la vigente es la de 0060_equity_operations
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.equity_cancel(p_operation uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare r erp.equity_operations; v_e uuid;
begin
  select * into r from erp.equity_operations where id = p_operation;
  if not found then raise exception 'Equity operation not found'; end if;
  if not erp.can_write(r.company_id) then raise exception 'No permission to change equity operations in this company'; end if;
  if r.status <> 'posted' then raise exception 'The operation is already cancelled'; end if;
  perform pg_advisory_xact_lock(hashtext('equity/' || r.company_id));
  if exists (select 1 from erp.equity_operations x where x.company_id = r.company_id and x.status = 'posted' and x.code > r.code) then
    raise exception 'Undo the later equity operations first (from the last one)';
  end if;
  if exists (select 1 from erp.fiscal_years f where f.company_id = r.company_id and r.op_date between f.starting_date and f.ending_date and f.status = 'closed') then
    raise exception 'The year of this operation is closed: reopen it first';
  end if;
  foreach v_e in array r.entry_ids loop
    perform erp.adjust_reverse(v_e, r.op_date, 'Deshacer ' || r.code);
  end loop;
  update erp.equity_operations set status = 'cancelled' where id = r.id;
end $function$
;
