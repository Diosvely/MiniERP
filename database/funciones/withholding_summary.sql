-- =====================================================================
-- erp.withholding_summary · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0018_withholding_exempt   →   la vigente es la de 0018_withholding_exempt
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.withholding_summary(p_company uuid, p_year integer, p_quarter integer)
 RETURNS TABLE(side text, form text, withholding_code text, rate_pct numeric, recipients integer, base numeric, amount numeric)
 LANGUAGE sql
 STABLE
AS $function$
  select r.side, case r.side when 'withheld' then r.form end, r.withholding_code, r.rate_pct,
         count(distinct r.partner_id)::int, sum(r.withholding_base), sum(r.withholding_amount)
  from erp.v_withholding_register r
  where r.company_id = p_company and r.fiscal_year = p_year and r.quarter = p_quarter
  group by r.side, r.form, r.withholding_code, r.rate_pct
  order by r.side desc, r.form, r.withholding_code;
$function$
;
