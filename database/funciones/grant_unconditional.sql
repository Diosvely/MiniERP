-- =====================================================================
-- erp.grant_unconditional · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0064_grants   →   la vigente es la de 0064_grants
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.grant_unconditional(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare g erp.grants; v_date date := (p->>'date')::date; v_tax numeric := 0; v_entry uuid;
begin
  select * into g from erp.grants where id = (p->>'grant_id')::uuid;
  if not found then raise exception 'Grant not found'; end if;
  perform erp.grant_check(g.company_id, v_date);
  if g.status <> 'active' then raise exception 'The grant is not active (%)', g.status; end if;
  if not g.refundable then raise exception 'The grant is not refundable'; end if;
  if (erp.grant_position(g.id)->>'unconditional')::boolean then raise exception 'The grant is already non-refundable'; end if;
  if v_date < (erp.grant_position(g.id)->>'last_date')::date then raise exception 'The date is earlier than the last posting of this grant'; end if;
  if g.kind = 'capital' then v_tax := round(g.amount * g.tax_rate / 100, 2); end if;
  v_entry := erp.equity_entry(g.company_id, v_date, 'La subvención deja de ser reintegrable · ' || g.description, g.code,
               jsonb_build_array(erp.equity_line(g.debt_account_id, g.amount, 0), erp.equity_line(g.income_account_id, 0, g.amount),
                                 erp.equity_line(g.tax_account_id, v_tax, 0), erp.equity_line(g.deferred_account_id, 0, v_tax)));
  insert into erp.grant_events (grant_id, company_id, kind, event_date, amount, tax_amount, entry_id)
  values (g.id, g.company_id, 'unconditional', v_date, g.amount, v_tax, v_entry);
  return jsonb_build_object('code', g.code, 'tax', v_tax, 'entry_no', (select entry_no from erp.journal_entries where id = v_entry));
end $function$
;
