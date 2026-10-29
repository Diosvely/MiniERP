-- =====================================================================
-- erp.grant_cancel · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0064_grants   →   la vigente es la de 0064_grants
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.grant_cancel(p_grant uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare g erp.grants; ev erp.grant_events;
begin
  select * into g from erp.grants where id = p_grant;
  if not found then raise exception 'Grant not found'; end if;
  if not erp.can_write(g.company_id) then raise exception 'No permission to change grants in this company'; end if;
  perform pg_advisory_xact_lock(hashtext('grants/' || g.company_id));
  select * into ev from erp.grant_events where grant_id = p_grant and status = 'posted' order by seq desc limit 1;
  if not found then raise exception 'The grant is already cancelled'; end if;
  if exists (select 1 from erp.fiscal_years f where f.company_id = g.company_id and ev.event_date between f.starting_date and f.ending_date and f.status = 'closed') then
    raise exception 'The year of this posting is closed: reopen it first';
  end if;
  if ev.entry_id is not null then perform erp.adjust_reverse(ev.entry_id, ev.event_date, 'Deshacer ' || g.code); end if;
  update erp.grant_events set status = 'cancelled' where id = ev.id;
  update erp.grants set status = case when ev.kind = 'concession' then 'cancelled' else 'active' end where id = g.id;
  return jsonb_build_object('code', g.code, 'kind', ev.kind, 'date', ev.event_date);
end $function$
;
