-- =====================================================================
-- erp.equity_status · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0060_equity_operations   →   la vigente es la de 0060_equity_operations
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.equity_status(p_company uuid, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare v_form text; v_cap numeric;
begin
  if not erp.can_read(p_company) then raise exception 'No permission to read this company'; end if;
  select legal_form into v_form from erp.companies where id = p_company;
  v_cap := erp.equity_bal(p_company, '100', p_date);
  return jsonb_build_object(
    'legal_form', v_form, 'date', p_date,
    'capital', v_cap,
    'uncalled', -erp.equity_bal(p_company, '1030', p_date),
    'called_unpaid', -erp.equity_bal(p_company, '5580', p_date),
    'premium', erp.equity_bal(p_company, '110', p_date),
    'legal_reserve', erp.equity_bal(p_company, '112', p_date),
    'voluntary_reserves', erp.equity_bal(p_company, '113', p_date),
    'prior_losses', -erp.equity_bal(p_company, '121', p_date),
    'result_to_distribute', erp.equity_bal(p_company, '129', p_date),
    'interim_dividend', -erp.equity_bal(p_company, '557', p_date),
    'dividend_payable', erp.equity_bal(p_company, '526', p_date),
    'net_worth', erp.equity_net_worth(p_company, p_date),
    'legal_reserve_cap', case when v_form = 'sl' and v_cap < 3000 then greatest(0, 3000 - v_cap) else round(v_cap * 0.20, 2) end,
    'low_capital_sl', v_form = 'sl' and v_cap < 3000,
    'cash', -erp.equity_bal(p_company, '57', p_date));
end $function$
;
