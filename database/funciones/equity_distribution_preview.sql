-- =====================================================================
-- erp.equity_distribution_preview · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0060_equity_operations 0095_equity_and_company_rules   →   la vigente es la de 0095_equity_and_company_rules
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.equity_distribution_preview(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  v_company uuid := (p->>'company_id')::uuid; v_date date := (p->>'date')::date;
  v_form text; v_res numeric; v_cap numeric; v_res112 numeric; v_losses numeric; v_interim numeric; v_nw numeric;
  v_offset numeric; v_legal_full numeric; v_legal_min numeric; v_legal numeric; v_div numeric; v_avail numeric; v_vol numeric;
  v_warn jsonb := '[]'; v_ok boolean := true; v_below boolean; v_min10 numeric;
begin
  if not erp.can_read(v_company) then raise exception 'No permission to read this company'; end if;
  select legal_form into v_form from erp.companies where id = v_company;
  v_res := erp.equity_bal(v_company, '129', v_date);
  v_cap := erp.equity_bal(v_company, '100', v_date);
  v_res112 := erp.equity_bal(v_company, '112', v_date);
  v_losses := -erp.equity_bal(v_company, '121', v_date);
  v_interim := -erp.equity_bal(v_company, '557', v_date);
  v_nw := erp.equity_net_worth(v_company, v_date, false) + v_interim;   -- antes del reparto (el dividendo a cuenta es parte del dividendo)
  v_div := round(coalesce((p->>'dividend')::numeric, v_interim), 2);
  if v_res = 0 then
    return jsonb_build_object('result', 0, 'ok', false, 'warnings', jsonb_build_array(jsonb_build_object('code', 'no_result')));
  end if;
  if v_res < 0 then
    -- pérdida: a la 121 y nada más
    if v_div > 0 or v_interim > 0 then v_ok := false; v_warn := v_warn || jsonb_build_object('code', 'dividend_with_loss'); end if;
    return jsonb_build_object('result', v_res, 'loss', -v_res, 'legal_reserve', 0, 'legal_reserve_min', 0, 'offset_losses', 0,
      'dividend', 0, 'interim', v_interim, 'complementary', 0, 'voluntary', 0, 'net_worth_before', v_nw, 'net_worth_after', v_nw,
      'capital', v_cap, 'ok', v_ok, 'warnings', v_warn, 'legal_form', v_form);
  end if;
  -- beneficio: si las pérdidas dejan el patrimonio neto por debajo del capital, primero compensar (art. 273.2 LSC y
  -- art. 28.3 Resolución ICAC 5-3-2019); si no, primero la reserva legal (art. 274.1 LSC), y el resto puede compensar
  -- pérdidas (v0.60.6, AF-11 y AF-14)
  v_legal_full := erp.equity_legal_reserve(v_form, v_cap, v_res112, v_res);
  v_below := v_losses > 0 and v_nw < v_cap;
  if v_below then
    v_offset := least(v_losses, v_res, coalesce((p->>'offset_losses')::numeric, v_losses));
    if v_offset < least(v_losses, v_res) then
      v_ok := false; v_warn := v_warn || jsonb_build_object('code', 'losses_must_be_offset', 'min', least(v_losses, v_res));
    end if;
    v_legal_min := least(v_legal_full, greatest(0, v_res - v_offset));
    if v_legal_min < v_legal_full then
      v_warn := v_warn || jsonb_build_object('code', 'losses_before_legal_reserve', 'min', v_legal_min);
    end if;
  else
    v_legal_min := v_legal_full;
    v_offset := least(v_losses, greatest(0, v_res - v_legal_min), coalesce((p->>'offset_losses')::numeric, v_losses));
  end if;
  v_legal := round(coalesce((p->>'legal_reserve')::numeric, v_legal_min), 2);
  if v_legal < v_legal_min then v_ok := false; v_warn := v_warn || jsonb_build_object('code', 'legal_reserve_below_min', 'min', v_legal_min); end if;
  v_avail := v_res - v_offset - v_legal;
  v_vol := v_avail - v_div;
  if v_div < v_interim then v_ok := false; v_warn := v_warn || jsonb_build_object('code', 'dividend_below_interim', 'interim', v_interim); end if;
  if v_vol < 0 then v_ok := false; v_warn := v_warn || jsonb_build_object('code', 'dividend_above_available', 'available', v_avail); end if;
  -- art. 273.2: después del reparto, el patrimonio neto no puede quedar por debajo del capital (AF-15, opción b: quedar
  -- pérdidas sin compensar ya no lo impide por sí solo)
  if v_div > 0 and v_nw - v_div < v_cap then
    v_ok := false; v_warn := v_warn || jsonb_build_object('code', 'net_worth_below_capital', 'net_worth_after', v_nw - v_div, 'capital', v_cap);
  end if;
  -- art. 326 (AF-13): después de una reducción de capital por pérdidas, siempre, la reserva legal al 10 % del capital
  if v_div > 0 and exists (select 1 from erp.equity_operations o where o.company_id = v_company and o.kind = 'capital_reduction'
                           and o.status = 'posted' and o.op_date <= v_date) then
    v_min10 := round(v_cap * 0.10, 2);
    if v_res112 + v_legal < v_min10 then
      v_ok := false; v_warn := v_warn || jsonb_build_object('code', 'legal_reserve_below_10_after_reduction', 'min', v_min10 - v_res112);
    end if;
  end if;
  if v_losses > 0 and v_offset < v_losses then v_warn := v_warn || jsonb_build_object('code', 'losses_left', 'left', v_losses - v_offset); end if;
  return jsonb_build_object('result', v_res, 'loss', 0, 'offset_losses', v_offset, 'legal_reserve', v_legal, 'legal_reserve_min', v_legal_min,
    'dividend', v_div, 'interim', v_interim, 'complementary', v_div - v_interim, 'voluntary', v_vol, 'available', v_avail,
    'net_worth_before', v_nw, 'net_worth_after', v_nw - v_div, 'capital', v_cap, 'legal_reserve_before', v_res112,
    'low_capital_sl', v_form = 'sl' and v_cap < 3000, 'ok', v_ok, 'warnings', v_warn, 'legal_form', v_form);
end $function$
;
