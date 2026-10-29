-- =====================================================================
-- erp.corporate_tax_calc · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0057_corporate_tax 0061_equity_integration   →   la vigente es la de 0061_equity_integration
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.corporate_tax_calc(p_company uuid, p_year integer, p_regime text DEFAULT NULL::text, p_recognize boolean DEFAULT NULL::boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET jit TO 'off'
AS $function$
declare
  v_fy erp.fiscal_years; v_ret erp.corporate_tax_returns; v_hint jsonb; v_regime text; v_recognize boolean;
  v_adj jsonb; v_result numeric; v_perm numeric; v_tinc numeric; v_tdec numeric; v_prev numeric;
  v_limit numeric; v_avail numeric; v_comp numeric := 0; v_usage jsonb := '[]'; v_left numeric; b record;
  v_base numeric; v_q jsonb; v_quota numeric; v_rate numeric; v_wh numeric; v_diff numeric;
  v_loss numeric; v_credit numeric; v_credit_used numeric := 0; v_def numeric; v_warn jsonb := '[]';
  v_eq numeric; v_eqtax numeric := 0;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;
  if not found then raise exception 'No fiscal year % in this company', p_year; end if;
  select * into v_ret from erp.corporate_tax_returns where fiscal_year_id = v_fy.id;
  if v_ret.status = 'posted' then return v_ret.result || jsonb_build_object('status', 'posted', 'return_id', v_ret.id); end if;
  v_hint := erp.corporate_tax_regime_hint(p_company, p_year);
  v_regime := coalesce(p_regime, v_ret.regime, v_hint->>'suggested');
  v_recognize := coalesce(p_recognize, v_ret.recognize_loss_credit, false);

  -- ajustes: los de la declaración (borrador) o los propuestos
  if v_ret.id is not null then
    select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'origin', a.origin, 'source_id', a.source_id, 'kind', a.kind,
             'direction', a.direction, 'concept', a.concept, 'amount', a.amount, 'article', a.article, 'included', a.included,
             'auto', a.auto) order by a.auto desc, a.origin, a.created_at), '[]') into v_adj
    from erp.corporate_tax_adjustments a where a.return_id = v_ret.id;
  else
    select coalesce(jsonb_agg(jsonb_build_object('id', null, 'origin', x.origin, 'source_id', x.source_id, 'kind', x.kind,
             'direction', x.direction, 'concept', x.concept, 'amount', x.amount, 'article', x.article, 'included', x.included,
             'auto', true)), '[]') into v_adj
    from erp.corporate_tax_proposals(p_company, p_year) x;
  end if;

  v_result := erp.pre_tax_result(p_company, v_fy.id);
  select coalesce(sum(case x->>'direction' when 'increase' then 1 else -1 end * (x->>'amount')::numeric) filter (where x->>'kind' = 'permanent'), 0),
         coalesce(sum((x->>'amount')::numeric) filter (where x->>'kind' = 'temporary' and x->>'direction' = 'increase'), 0),
         coalesce(sum((x->>'amount')::numeric) filter (where x->>'kind' = 'temporary' and x->>'direction' = 'decrease'), 0)
    into v_perm, v_tinc, v_tdec
  from jsonb_array_elements(v_adj) x where (x->>'included')::boolean;
  v_prev := v_result + v_perm + v_tinc - v_tdec;

  -- compensación de bases negativas (art. 26.1): hasta el 70 % de la base previa, y en todo caso 1 millón
  select coalesce(sum(pending), 0) into v_avail from erp.corporate_tax_loss_carryforwards(p_company, p_year);
  v_limit := case when v_prev > 0 then greatest(round(v_prev * 0.70, 2), least(v_prev, 1000000)) else 0 end;
  v_left := least(v_avail, v_limit, greatest(v_prev, 0));
  for b in select * from erp.corporate_tax_loss_carryforwards(p_company, p_year) loop
    exit when v_left <= 0;
    v_usage := v_usage || jsonb_build_object('origin_year', b.origin_year, 'amount', least(b.pending, v_left));
    if b.credit_rate is not null then v_credit_used := v_credit_used + round(least(b.pending, v_left) * b.credit_rate / 100, 2); end if;
    v_comp := v_comp + least(b.pending, v_left);
    v_left := v_left - least(b.pending, v_left);
  end loop;
  v_base := v_prev - v_comp;

  v_q := erp.corporate_tax_quota(p_year, v_regime, greatest(v_base, 0));
  v_quota := (v_q->>'quota')::numeric;
  v_rate := (v_q->>'marginal_rate')::numeric;
  -- retenciones y pagos fraccionados: saldo deudor de la 473 al cierre
  select coalesce(sum(l.debit - l.credit), 0) into v_wh
  from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id join erp.gl_accounts g on g.id = l.gl_account_id
  where e.company_id = p_company and e.fiscal_year_id = v_fy.id and e.status = 'posted'
    and e.entry_type not in ('closing_pl', 'closing') and g.account_no like '473%';
  v_diff := v_quota - v_wh;
  -- v0.42.0 · gastos cargados a reservas (113): el impuesto que ahorran va también contra reservas, no a la PyG (NRV 13.ª,
  -- apdo. 2.1): el gasto por impuesto corriente (6300) es el de la base sin ellos y la diferencia va a la 113 al Haber
  select coalesce(sum((x->>'amount')::numeric), 0) into v_eq
  from jsonb_array_elements(v_adj) x where (x->>'included')::boolean and x->>'origin' = 'equity_costs';
  if v_eq > 0 then
    v_eqtax := ((erp.corporate_tax_quota(p_year, v_regime, greatest(v_base + v_eq, 0)))->>'quota')::numeric - v_quota;
  end if;

  -- impuesto diferido (NRV 13.ª): diferencias temporarias × tipo; bases negativas, solo si se registra el crédito
  v_loss := greatest(-v_prev, 0);
  v_credit := case when v_recognize then round(v_loss * v_rate / 100, 2) else 0 end;
  v_def := round(v_tdec * v_rate / 100, 2) - round(v_tinc * v_rate / 100, 2) - v_credit + v_credit_used;

  if v_regime <> v_hint->>'suggested' and not (v_regime = 'new_entity')
     and not (v_regime = 'erd' and v_hint->>'suggested' = 'micro') then
    v_warn := v_warn || jsonb_build_object('code', 'regime_mismatch', 'suggested', v_hint->>'suggested', 'turnover', v_hint->'turnover');
  end if;
  if v_regime in ('micro', 'erd') and not (v_hint->>'is_erd')::boolean then
    v_warn := v_warn || jsonb_build_object('code', 'regime_not_allowed', 'turnover', v_hint->'turnover');
  end if;
  if v_wh < 0 then v_warn := v_warn || jsonb_build_object('code', 'withholdings_credit_balance', 'amount', v_wh); end if;
  if v_loss > 0 and not v_recognize then v_warn := v_warn || jsonb_build_object('code', 'loss_credit_not_recognized', 'amount', v_loss); end if;

  return jsonb_build_object(
    'status', coalesce(v_ret.status, 'none'), 'return_id', v_ret.id, 'year', p_year, 'regime', v_regime,
    'recognize_loss_credit', v_recognize, 'hint', v_hint,
    'pre_tax_result', v_result, 'adjustments', v_adj,
    'permanent', v_perm, 'temporary_increase', v_tinc, 'temporary_decrease', v_tdec,
    'base_before_losses', v_prev, 'losses_available', v_avail, 'losses_limit', v_limit,
    'losses_compensated', v_comp, 'loss_usage', v_usage, 'taxable_base', v_base,
    'quota', v_quota, 'brackets', v_q->'brackets', 'rates_year', v_q->'rates_year',
    'withholdings', v_wh, 'differential', v_diff,
    'outcome', case when v_diff > 0 then 'pay' when v_diff < 0 then 'refund' else 'zero' end,
    'deferred_rate', v_rate, 'loss_generated', v_loss, 'loss_credit', v_credit, 'loss_credit_used', v_credit_used,
    'current_tax', v_quota + v_eqtax, 'deferred_tax', v_def, 'tax_expense', v_quota + v_eqtax + v_def,
    'equity_costs', v_eq, 'equity_tax_effect', v_eqtax,
    'net_result', v_result - v_quota - v_eqtax - v_def, 'warnings', v_warn);
end $function$
;
