-- =====================================================================
-- erp.corporate_tax_regime_hint · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0057_corporate_tax 0098_regime_hint_annualized   →   la vigente es la de 0098_regime_hint_annualized
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.corporate_tax_regime_hint(p_company uuid, p_year integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET jit TO 'off'
AS $function$
declare v_fy erp.fiscal_years; v_prev erp.fiscal_years; v_basis numeric; v_by int; v_start date; v_days int; v_annual boolean := false;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;
  if not found then raise exception 'No fiscal year % in this company', p_year; end if;
  select * into v_prev from erp.fiscal_years where company_id = p_company and year = p_year - 1;
  if found then
    v_basis := erp.net_turnover(p_company, v_prev.id); v_by := p_year - 1;
    -- v0.60.9 (AF-27): el período impositivo del año anterior, si se guardó uno más corto
    select r.period_start into v_start from erp.corporate_tax_returns r
    where r.company_id = p_company and r.fiscal_year_id = v_prev.id and r.period_start is not null
    order by r.created_at desc limit 1;
    v_days := least((v_prev.ending_date - coalesce(v_start, v_prev.starting_date)) + 1, 365);
    if v_days < 365 and v_basis <> 0 then
      v_basis := round(v_basis * 365 / v_days, 2);
      v_annual := true;
    end if;
  else
    v_basis := erp.net_turnover(p_company, v_fy.id); v_by := p_year;
  end if;
  return jsonb_build_object('turnover', v_basis, 'basis_year', v_by, 'basis_days', v_days, 'annualized', v_annual,
    'suggested', case when v_basis < 1000000 then 'micro' when v_basis < 10000000 then 'erd' else 'general' end,
    'is_erd', v_basis < 10000000, 'is_micro', v_basis < 1000000);
end $function$
;
