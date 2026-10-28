-- =====================================================================
-- erp.grant_collect · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0064_grants   →   la vigente es la de 0064_grants
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.grant_collect(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare g erp.grants; v_date date := (p->>'date')::date; v_entry uuid;
begin
  select * into g from erp.grants where id = (p->>'grant_id')::uuid;
  if not found then raise exception 'Grant not found'; end if;
  perform erp.grant_check(g.company_id, v_date);
  if g.status = 'cancelled' then raise exception 'The grant is cancelled'; end if;
  if (erp.grant_position(g.id)->>'collected')::boolean then raise exception 'The grant is already collected'; end if;
  if v_date < (erp.grant_position(g.id)->>'last_date')::date then raise exception 'The date is earlier than the last posting of this grant'; end if;
  v_entry := erp.equity_entry(g.company_id, v_date, 'Cobro de la subvención · ' || g.description, g.code,
               jsonb_build_array(erp.equity_line(erp.equity_bank(g.company_id, p->>'bank_account_no'), g.amount, 0),
                                 erp.equity_line(g.receivable_account_id, 0, g.amount)));
  insert into erp.grant_events (grant_id, company_id, kind, event_date, amount, entry_id) values (g.id, g.company_id, 'collection', v_date, g.amount, v_entry);
  return jsonb_build_object('code', g.code, 'entry_no', (select entry_no from erp.journal_entries where id = v_entry));
end $function$
;
