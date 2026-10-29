-- =====================================================================
-- erp.equity_loss_offset · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0060_equity_operations   →   la vigente es la de 0060_equity_operations
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.equity_loss_offset(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare v_company uuid := (p->>'company_id')::uuid; v_date date := (p->>'date')::date; v_code text; v_amt numeric; v_losses numeric; v_vol numeric; e1 uuid;
begin
  v_code := erp.equity_start(v_company, v_date);
  v_amt := round(coalesce((p->>'amount')::numeric, 0), 2);
  v_losses := -erp.equity_bal(v_company, '121', v_date); v_vol := erp.equity_bal(v_company, '113', v_date);
  if v_amt <= 0 or v_amt > v_losses then raise exception 'The amount must be between 0 and the pending losses (%)', v_losses; end if;
  if v_amt > v_vol then raise exception 'Not enough voluntary reserves (balance %)', v_vol; end if;
  e1 := erp.equity_entry(v_company, v_date, 'Compensación de pérdidas con reservas voluntarias', v_code,
          jsonb_build_array(erp.equity_line((select g.id from erp.gl_accounts g where g.company_id = v_company and g.account_type = 'posting' and g.account_no like '113%'
                                             order by (select coalesce(sum(l.credit - l.debit), 0) from erp.journal_lines l where l.gl_account_id = g.id) desc limit 1), v_amt, 0),
            erp.equity_line((select id from erp.gl_accounts where company_id = v_company and account_type = 'posting' and account_no like '121%' order by account_no limit 1), 0, v_amt)));
  return erp.equity_save(v_company, v_code, 'loss_offset', v_date, 'Compensación de pérdidas', p,
    jsonb_build_object('amount', v_amt, 'losses_after', v_losses - v_amt), array[e1]);
end $function$
;
