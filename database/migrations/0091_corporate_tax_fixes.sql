-- =====================================================================
-- 0091 · Impuesto sobre Sociedades: tipos de la microempresa y tramo por días (v0.60.2)
-- ---------------------------------------------------------------------
-- Hallazgos del chat de auditoría fiscal AF-02 y AF-03 (08-11-2026), aprobados por Diosvely (diseno-v0.60.2.md).
-- Norma: art. 29.1 y DT 44.ª LIS, en la redacción de la Ley 7/2024, DF 8.ª (BOE núm. 307, de 21-12-2024).
--   1. AF-02 · La microempresa (cifra de negocios del período anterior < 1 millón) solo tenía los tipos de 2026. Faltaban
--      2025 (21 % / 22 %, DT 44.ª) y desde 2027 los del art. 29.1 (17 % / 20 %): en 2025 el cálculo daba error y desde
--      2027 aplicaba los de 2026.
--   2. AF-03 · Si el período impositivo dura menos de un año, el tramo al tipo reducido es 50.000 × días / 365. El
--      ejercicio del ERP va siempre de enero a diciembre: la declaración guarda dónde empieza el período impositivo
--      (period_start; vacío = el ejercicio entero) y erp.corporate_tax_period lo cambia mientras es un borrador.
--      erp.corporate_tax_quota recibe los días (por defecto, 365) y erp.corporate_tax_calc se los pasa.
-- Pruebas: test_fase52_corporate_tax.sql (regresión de los tipos y del tramo por días).
-- Re-ejecutable.
-- =====================================================================

-- ---------- 1. Tipos de la microempresa (AF-02) ----------
insert into erp.corporate_tax_rates (valid_from_year, regime, upto, rate) values
(2025, 'micro', 50000, 21), (2025, 'micro', null, 22),
(2027, 'micro', 50000, 17), (2027, 'micro', null, 20)
on conflict (valid_from_year, regime, rate) do update set upto = excluded.upto;

-- ---------- 2. Período impositivo de la declaración (AF-03) ----------
alter table erp.corporate_tax_returns add column if not exists period_start date;
comment on column erp.corporate_tax_returns.period_start is
  'Start of the tax period when it is shorter than the fiscal year (e.g. the first year of a company, art. 29.1 LIS). Null = the whole fiscal year.';

-- El tramo con límite (la microempresa) se reparte por días: límite × días / 365, al céntimo (art. 29.1 LIS)
drop function if exists erp.corporate_tax_quota(int, text, numeric);
create or replace function erp.corporate_tax_quota(p_year int, p_regime text, p_base numeric, p_days int default 365)
returns jsonb language plpgsql stable set jit = off as $$
declare r record; v_from int; v_prev numeric := 0; v_quota numeric := 0; v_marginal numeric; v_rows jsonb := '[]';
  v_days int := least(greatest(coalesce(p_days, 365), 1), 365); v_upto numeric;
begin
  select max(valid_from_year) into v_from from erp.corporate_tax_rates where valid_from_year <= p_year and regime = p_regime;
  if v_from is null then raise exception 'No corporate tax rates for % (%): add them to erp.corporate_tax_rates', p_year, p_regime; end if;
  for r in select upto, rate from erp.corporate_tax_rates where valid_from_year = v_from and regime = p_regime
           order by upto nulls last loop
    v_upto := case when r.upto is null or v_days >= 365 then r.upto else round(r.upto * v_days / 365, 2) end;
    if v_marginal is null or p_base > v_prev then v_marginal := r.rate; end if;
    if p_base > v_prev then
      v_quota := v_quota + round((least(p_base, coalesce(v_upto, p_base)) - v_prev) * r.rate / 100, 2);
      v_rows := v_rows || jsonb_build_object('from', v_prev, 'upto', v_upto, 'rate', r.rate,
                                             'base', least(p_base, coalesce(v_upto, p_base)) - v_prev);
    end if;
    v_prev := coalesce(v_upto, v_prev);
  end loop;
  return jsonb_build_object('quota', v_quota, 'marginal_rate', v_marginal, 'brackets', v_rows, 'rates_year', v_from, 'days', v_days);
end $$;

-- El cálculo pasa los días del período (y dice cuál es y si hay una fecha que sugerir)
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
  v_start date; v_days int; v_cstart date;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;
  if not found then raise exception 'No fiscal year % in this company', p_year; end if;
  select * into v_ret from erp.corporate_tax_returns where fiscal_year_id = v_fy.id;
  if v_ret.status = 'posted' then return v_ret.result || jsonb_build_object('status', 'posted', 'return_id', v_ret.id); end if;
  v_hint := erp.corporate_tax_regime_hint(p_company, p_year);
  v_regime := coalesce(p_regime, v_ret.regime, v_hint->>'suggested');
  v_recognize := coalesce(p_recognize, v_ret.recognize_loss_credit, false);
  -- v0.60.2 · período impositivo (art. 29.1 LIS): por defecto, el ejercicio entero; si empieza más tarde (el primer
  -- ejercicio de una sociedad), el tramo reducido se reparte por días. La fecha de inicio de la contabilidad solo se sugiere
  v_start := coalesce(v_ret.period_start, v_fy.starting_date);
  v_days := least((v_fy.ending_date - v_start) + 1, 365);
  select c.start_date into v_cstart from erp.companies c where c.id = p_company;

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

  v_q := erp.corporate_tax_quota(p_year, v_regime, greatest(v_base, 0), v_days);
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
    v_eqtax := ((erp.corporate_tax_quota(p_year, v_regime, greatest(v_base + v_eq, 0), v_days))->>'quota')::numeric - v_quota;
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
    'period_start', v_start, 'period_end', v_fy.ending_date, 'period_days', v_days,
    'suggested_start', case when v_cstart > v_fy.starting_date and v_cstart <= v_fy.ending_date and v_cstart <> v_start
                            and v_ret.period_start is null then v_cstart end,
    'withholdings', v_wh, 'differential', v_diff,
    'outcome', case when v_diff > 0 then 'pay' when v_diff < 0 then 'refund' else 'zero' end,
    'deferred_rate', v_rate, 'loss_generated', v_loss, 'loss_credit', v_credit, 'loss_credit_used', v_credit_used,
    'current_tax', v_quota + v_eqtax, 'deferred_tax', v_def, 'tax_expense', v_quota + v_eqtax + v_def,
    'equity_costs', v_eq, 'equity_tax_effect', v_eqtax,
    'net_result', v_result - v_quota - v_eqtax - v_def, 'warnings', v_warn);
end $function$;

-- Cambiar el inicio del período impositivo (solo en borrador; null o el 1 de enero = el ejercicio entero)
create or replace function erp.corporate_tax_period(p_return uuid, p_start date)
returns void language plpgsql security definer set search_path = erp, public as $$
declare r erp.corporate_tax_returns; v_fy erp.fiscal_years;
begin
  r := erp.corporate_tax_draft(p_return);
  select * into v_fy from erp.fiscal_years where id = r.fiscal_year_id;
  if p_start is not null and (p_start < v_fy.starting_date or p_start > v_fy.ending_date) then
    raise exception 'The tax period must start within the fiscal year (% to %)', v_fy.starting_date, v_fy.ending_date;
  end if;
  update erp.corporate_tax_returns set period_start = nullif(p_start, v_fy.starting_date) where id = p_return;
end $$;

-- Sin sesión, ninguna función (0085): las nuevas o cambiadas, solo para quien tiene sesión
do $$
declare f text;
begin
  foreach f in array array['erp.corporate_tax_quota(integer, text, numeric, integer)', 'erp.corporate_tax_period(uuid, date)',
                           'erp.corporate_tax_calc(uuid, integer, text, boolean)'] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
