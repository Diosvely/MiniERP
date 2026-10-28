-- =====================================================================
-- erp.loan_calc · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0062_loans   →   la vigente es la de 0062_loans
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.loan_calc(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET jit TO 'off'
AS $function$
declare
  v_kind text := coalesce(p->>'kind', 'loan'); v_freq int := coalesce((p->>'frequency')::int, 12); v_n int := (p->>'periods')::int;
  v_start date := (p->>'start_date')::date; v_first date; v_rate numeric := coalesce((p->>'rate')::numeric, 0);
  v_months int; v_pays numeric[]; v_principal numeric; v_costs numeric := round(coalesce((p->>'costs')::numeric, 0), 2);
  v_net numeric; v_inst numeric; v_opt numeric := round(coalesce((p->>'purchase_option')::numeric, 0), 2);
  v_fv numeric; v_pv numeric; v_eff numeric; v_rows jsonb;
begin
  if v_kind not in ('loan', 'leasing') then raise exception 'Invalid kind: %', v_kind; end if;
  if v_freq not in (1, 2, 4, 12) then raise exception 'The frequency must be 1, 2, 4 or 12 instalments a year'; end if;
  if v_n is null or v_n < 1 or v_n > 600 then raise exception 'The number of instalments must be between 1 and 600'; end if;
  if v_start is null then raise exception 'The start date is required'; end if;
  if v_rate < 0 or v_rate > 100 then raise exception 'The interest rate must be between 0 and 100'; end if;
  v_months := 12 / v_freq;
  v_first := coalesce((p->>'first_due_date')::date, (v_start + make_interval(months => v_months))::date - 1);
  if v_first <= v_start or v_first > v_start + make_interval(months => v_months) then
    raise exception 'The first instalment must fall within the first period after the start date';
  end if;
  if v_kind = 'loan' then
    v_principal := round(coalesce((p->>'principal')::numeric, 0), 2);
    if v_principal <= 0 then raise exception 'The loan amount must be positive'; end if;
    if v_costs < 0 or v_costs >= v_principal then raise exception 'The costs must be between 0 and the loan amount'; end if;
    v_pays := erp.loan_french_payments(v_principal, v_rate / 100 / v_freq, v_n);
    v_net := v_principal - v_costs;
    v_eff := case when v_costs = 0 then v_rate / 100 / v_freq else erp.loan_effective_rate(v_pays, v_net) end;
    v_inst := v_pays[1];
  else
    v_fv := round(coalesce((p->>'fair_value')::numeric, 0), 2); v_inst := round(coalesce((p->>'instalment')::numeric, 0), 2);
    if v_fv <= 0 or v_inst <= 0 then raise exception 'The fair value and the instalment must be positive'; end if;
    if v_opt < 0 then raise exception 'The purchase option cannot be negative'; end if;
    select array_agg(case when t = v_n then v_inst + v_opt else v_inst end order by t) into v_pays from generate_series(1, v_n) t;
    if p ? 'rate' and v_rate > 0 then v_pv := round(erp.loan_present_value(v_pays, v_rate / 100 / v_freq), 2); end if;
    v_net := least(v_fv, coalesce(v_pv, v_fv));   -- NRV 8.ª: el menor
    v_principal := v_net;
    v_eff := erp.loan_effective_rate(v_pays, v_net);
  end if;
  select jsonb_agg(jsonb_build_object('n', r.n, 'due_date', (v_first + make_interval(months => v_months * (r.n - 1)))::date,
                                      'payment', r.payment, 'interest', r.interest, 'reduction', r.reduction, 'balance', r.balance) order by r.n)
  into v_rows from erp.loan_rows(v_pays, v_net, v_eff) r;
  return jsonb_build_object(
    'kind', v_kind, 'frequency', v_freq, 'periods', v_n, 'start_date', v_start, 'first_due_date', v_first,
    'nominal_rate', v_rate, 'principal', v_principal, 'costs', v_costs, 'net_amount', v_net, 'instalment', v_inst,
    'purchase_option', v_opt, 'fair_value', v_fv, 'present_value', v_pv,
    'effective_rate', v_eff, 'effective_rate_year', round((power(1 + v_eff, v_freq) - 1) * 100, 6),
    'total_interest', (select sum((x->>'interest')::numeric) from jsonb_array_elements(v_rows) x),
    'short_part', (select coalesce(sum((x->>'reduction')::numeric), 0) from jsonb_array_elements(v_rows) x
                   where (x->>'due_date')::date <= v_start + interval '1 year'),
    'schedule', v_rows);
end $function$
;
