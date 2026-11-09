-- =====================================================================
-- erp.corporate_tax_quota · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0057_corporate_tax 0091_corporate_tax_fixes   →   la vigente es la de 0091_corporate_tax_fixes
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.corporate_tax_quota(p_year integer, p_regime text, p_base numeric, p_days integer DEFAULT 365)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET jit TO 'off'
AS $function$
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
end $function$
;
