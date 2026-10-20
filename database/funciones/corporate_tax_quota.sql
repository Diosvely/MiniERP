-- =====================================================================
-- erp.corporate_tax_quota · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0057_corporate_tax   →   la vigente es la de 0057_corporate_tax
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.corporate_tax_quota(p_year integer, p_regime text, p_base numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
declare r record; v_from int; v_prev numeric := 0; v_quota numeric := 0; v_marginal numeric; v_rows jsonb := '[]';
begin
  select max(valid_from_year) into v_from from erp.corporate_tax_rates where valid_from_year <= p_year and regime = p_regime;
  if v_from is null then raise exception 'No corporate tax rates for % (%): add them to erp.corporate_tax_rates', p_year, p_regime; end if;
  for r in select upto, rate from erp.corporate_tax_rates where valid_from_year = v_from and regime = p_regime
           order by upto nulls last loop
    if v_marginal is null or p_base > v_prev then v_marginal := r.rate; end if;
    if p_base > v_prev then
      v_quota := v_quota + round((least(p_base, coalesce(r.upto, p_base)) - v_prev) * r.rate / 100, 2);
      v_rows := v_rows || jsonb_build_object('from', v_prev, 'upto', r.upto, 'rate', r.rate,
                                             'base', least(p_base, coalesce(r.upto, p_base)) - v_prev);
    end if;
    v_prev := coalesce(r.upto, v_prev);
  end loop;
  return jsonb_build_object('quota', v_quota, 'marginal_rate', v_marginal, 'brackets', v_rows, 'rates_year', v_from);
end $function$
;
