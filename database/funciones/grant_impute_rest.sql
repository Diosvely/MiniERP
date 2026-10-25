-- =====================================================================
-- erp.grant_impute_rest · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0064_grants   →   la vigente es la de 0064_grants
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.grant_impute_rest(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare g erp.grants; pos jsonb; v_date date := (p->>'date')::date; v_amt numeric; v_tax numeric; v_entry uuid;
begin
  select * into g from erp.grants where id = (p->>'grant_id')::uuid;
  if not found then raise exception 'Grant not found'; end if;
  perform erp.grant_check(g.company_id, v_date);
  if g.kind <> 'capital' or g.status <> 'active' then raise exception 'Only an active capital grant can be imputed'; end if;
  pos := erp.grant_position(g.id);
  if not (pos->>'unconditional')::boolean then raise exception 'The grant is still refundable'; end if;
  if v_date < (pos->>'last_date')::date then raise exception 'The date is earlier than the last posting of this grant'; end if;
  v_amt := g.amount - (pos->>'imputed')::numeric;
  v_tax := (pos->>'tax_recognised')::numeric - (pos->>'tax_reversed')::numeric;
  v_entry := erp.equity_entry(g.company_id, v_date, 'Subvención: lo pendiente, al resultado (baja del activo) · ' || g.description, g.code,
               jsonb_build_array(erp.equity_line(g.transfer_account_id, v_amt, 0), erp.equity_line(g.result_account_id, 0, v_amt),
                                 erp.equity_line(g.deferred_account_id, v_tax, 0), erp.equity_line(g.tax_account_id, 0, v_tax)));
  insert into erp.grant_events (grant_id, company_id, kind, event_date, amount, tax_amount, entry_id)
  values (g.id, g.company_id, 'disposal', v_date, v_amt, v_tax, v_entry);
  update erp.grants set status = 'imputed' where id = g.id;
  return jsonb_build_object('code', g.code, 'amount', v_amt, 'tax', v_tax, 'entry_no', (select entry_no from erp.journal_entries where id = v_entry));
end $function$
;
