-- =====================================================================
-- erp.equity_interim_preview · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0060_equity_operations 0095_equity_and_company_rules   →   la vigente es la de 0095_equity_and_company_rules
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.equity_interim_preview(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  v_company uuid := (p->>'company_id')::uuid; v_date date := (p->>'date')::date; v_form text;
  v_result numeric; v_losses numeric; v_tax numeric; v_legal numeric; v_max numeric; v_amt numeric; v_cash numeric; v_paid numeric; v_warn jsonb := '[]';
  v_cap numeric; v_res112 numeric;
begin
  if not erp.can_read(v_company) then raise exception 'No permission to read this company'; end if;
  select legal_form into v_form from erp.companies where id = v_company;
  v_result := erp.equity_bal(v_company, '6', v_date) + erp.equity_bal(v_company, '7', v_date);   -- antes de impuestos (sin 630)
  v_result := v_result - erp.equity_bal(v_company, '630', v_date);
  v_losses := -erp.equity_bal(v_company, '121', v_date);
  v_tax := round(coalesce((p->>'estimated_tax')::numeric, greatest(v_result, 0) * 0.25), 2);
  v_cap := erp.equity_bal(v_company, '100', v_date);
  v_res112 := erp.equity_bal(v_company, '112', v_date);
  v_legal := erp.equity_legal_reserve(v_form, v_cap, v_res112, v_result - v_tax);
  v_paid := -erp.equity_bal(v_company, '557', v_date);   -- dividendos a cuenta ya acordados este ejercicio
  v_max := greatest(0, v_result - v_losses - v_tax - v_legal - v_paid);
  v_amt := round(coalesce((p->>'amount')::numeric, 0), 2);
  v_cash := -erp.equity_bal(v_company, '57', v_date);
  if v_amt > v_max then v_warn := v_warn || jsonb_build_object('code', 'interim_above_limit', 'max', v_max); end if;
  if v_amt > v_cash then v_warn := v_warn || jsonb_build_object('code', 'interim_no_liquidity', 'cash', v_cash); end if;
  -- v0.60.6 (AF-13, art. 326 LSC): después de una reducción de capital por pérdidas, la reserva legal al 10 % del capital
  if v_amt > 0 and v_res112 < round(v_cap * 0.10, 2)
     and exists (select 1 from erp.equity_operations o where o.company_id = v_company and o.kind = 'capital_reduction'
                 and o.status = 'posted' and o.op_date <= v_date) then
    v_warn := v_warn || jsonb_build_object('code', 'legal_reserve_below_10_after_reduction', 'min', round(v_cap * 0.10, 2) - v_res112);
  end if;
  return jsonb_build_object('result_since_close', v_result, 'prior_losses', v_losses, 'estimated_tax', v_tax, 'legal_reserve', v_legal,
    'already_paid', v_paid, 'max', v_max, 'amount', v_amt, 'cash', v_cash, 'ok', v_amt > 0 and jsonb_array_length(v_warn) = 0, 'warnings', v_warn);
end $function$
;
