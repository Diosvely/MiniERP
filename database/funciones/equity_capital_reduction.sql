-- =====================================================================
-- erp.equity_capital_reduction · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0060_equity_operations   →   la vigente es la de 0060_equity_operations
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.equity_capital_reduction(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare
  v_company uuid := (p->>'company_id')::uuid; v_date date := (p->>'date')::date; v_code text; v_amt numeric; v_losses numeric;
  v_cap numeric; v_form text; e1 uuid;
begin
  v_code := erp.equity_start(v_company, v_date);
  select legal_form into v_form from erp.companies where id = v_company;
  v_amt := round(coalesce((p->>'amount')::numeric, 0), 2);
  v_losses := -erp.equity_bal(v_company, '121', v_date); v_cap := erp.equity_bal(v_company, '100', v_date);
  if v_amt <= 0 or v_amt > v_losses then raise exception 'The reduction must be between 0 and the pending losses (%)', v_losses; end if;
  if erp.equity_bal(v_company, '113', v_date) > 0 then raise exception 'Use the voluntary reserves first: capital cannot be reduced for losses while there are reserves (art. 322 LSC)'; end if;
  if erp.equity_bal(v_company, '112', v_date) > round((v_cap - v_amt) * 0.10, 2) then
    raise exception 'The legal reserve would exceed 10 %% of the new capital: use it first (art. 322 LSC)';
  end if;
  if v_cap - v_amt < (case v_form when 'sa' then 60000 else 1 end) then
    raise exception 'The capital would be below the legal minimum (art. 4 LSC)';
  end if;
  e1 := erp.equity_entry(v_company, v_date, 'Reducción de capital para compensar pérdidas', v_code,
          jsonb_build_array(erp.equity_line(erp.adjust_account(v_company, '100', 'Capital social'), v_amt, 0),
            erp.equity_line((select id from erp.gl_accounts where company_id = v_company and account_type = 'posting' and account_no like '121%' order by account_no limit 1), 0, v_amt)));
  return erp.equity_save(v_company, v_code, 'capital_reduction', v_date, 'Reducción de capital por pérdidas', p,
    jsonb_build_object('amount', v_amt, 'capital_after', v_cap - v_amt, 'losses_after', v_losses - v_amt), array[e1]);
end $function$
;
