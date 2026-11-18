-- =====================================================================
-- 0098 · v0.60.9 · La cifra de negocios de un año corto se eleva al año (AF-27)
-- ---------------------------------------------------------------------
-- Aprobado por Diosvely (18-11-2026). Ficha AF-27 de auditoría fiscal.
-- Para sugerir el régimen del Impuesto sobre Sociedades (microempresa, menos de 1 millón; reducida dimensión, menos de
-- 10 millones) el ERP usa la cifra de negocios del año anterior. Si el período impositivo de ese año duró menos de un
-- año (por ejemplo, el primero, de julio a diciembre), la cifra se eleva al año: cifra × 365 / días.
-- Norma: art. 101.2 LIS («Si el período impositivo inmediato anterior hubiere tenido una duración inferior al año… el
-- importe neto de la cifra de negocios se elevará al año»); el art. 29.1 remite al 101.2 y 3 para la microempresa (Ley
-- 27/2014, BOE consolidado, última modificación 02-09-2026).
-- Sin ejercicio anterior (la sociedad nueva usa su primer período, art. 101.2, primera frase) no se eleva: queda
-- pendiente de validar si la segunda frase lo exigiría (ADR 0040).
-- Prueba: fase 52.
-- =====================================================================

create or replace function erp.corporate_tax_regime_hint(p_company uuid, p_year integer)
 returns jsonb
 language plpgsql
 stable
 set jit to 'off'
as $function$
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
end $function$;
