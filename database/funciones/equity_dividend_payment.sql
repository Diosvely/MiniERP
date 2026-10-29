-- =====================================================================
-- erp.equity_dividend_payment · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0060_equity_operations   →   la vigente es la de 0060_equity_operations
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.equity_dividend_payment(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  v_company uuid := (p->>'company_id')::uuid; v_date date := (p->>'date')::date; v_code text; v_pending numeric; v_amt numeric;
  v_pct numeric; v_wh numeric; e1 uuid; v_reason text := nullif(btrim(p->>'no_withholding_reason'), '');
begin
  v_code := erp.equity_start(v_company, v_date);
  v_pending := erp.equity_bal(v_company, '526', v_date);
  v_amt := round(coalesce((p->>'amount')::numeric, v_pending), 2);
  if v_amt <= 0 or v_amt > v_pending then raise exception 'The payment must be between 0 and the dividend payable (%)', v_pending; end if;
  v_pct := case when v_reason is not null then 0 else coalesce((p->>'withholding_pct')::numeric, 19) end;
  if v_pct <> 0 and v_pct <> 19 then raise exception 'The withholding on dividends is 19 %% (art. 101.4 LIRPF) or none with its reason'; end if;
  if v_pct = 0 and v_reason is null then raise exception 'Without withholding, say why (e.g. exemption of art. 21 LIS)'; end if;
  v_wh := round(v_amt * v_pct / 100, 2);
  e1 := erp.equity_entry(v_company, v_date, 'Pago del dividendo' || case when v_wh > 0 then ' (retención del 19 %, modelo 123)' else ' (sin retención: ' || v_reason || ')' end, v_code,
          jsonb_build_array(erp.equity_line((select id from erp.gl_accounts where company_id = v_company and account_type = 'posting' and account_no like '526%' order by account_no limit 1), v_amt, 0),
            erp.equity_line(case when v_wh > 0 then erp.adjust_account(v_company, '47512', 'HP acreedora por retenciones de dividendos (modelo 123)') end, 0, v_wh),
            erp.equity_line(erp.equity_bank(v_company, p->>'bank_account_no'), 0, v_amt - v_wh)));
  return erp.equity_save(v_company, v_code, 'dividend_payment', v_date, 'Pago del dividendo', p,
    jsonb_build_object('gross', v_amt, 'withholding', v_wh, 'net', v_amt - v_wh, 'pending_after', v_pending - v_amt), array[e1]);
end $function$
;
