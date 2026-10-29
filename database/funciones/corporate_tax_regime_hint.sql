-- =====================================================================
-- erp.corporate_tax_regime_hint · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0057_corporate_tax   →   la vigente es la de 0057_corporate_tax
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.corporate_tax_regime_hint(p_company uuid, p_year integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET jit TO 'off'
AS $function$
declare v_fy erp.fiscal_years; v_prev erp.fiscal_years; v_basis numeric; v_by int;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;
  if not found then raise exception 'No fiscal year % in this company', p_year; end if;
  select * into v_prev from erp.fiscal_years where company_id = p_company and year = p_year - 1;
  if found then v_basis := erp.net_turnover(p_company, v_prev.id); v_by := p_year - 1;
  else v_basis := erp.net_turnover(p_company, v_fy.id); v_by := p_year; end if;
  return jsonb_build_object('turnover', v_basis, 'basis_year', v_by,
    'suggested', case when v_basis < 1000000 then 'micro' when v_basis < 10000000 then 'erd' else 'general' end,
    'is_erd', v_basis < 10000000, 'is_micro', v_basis < 1000000);
end $function$
;
