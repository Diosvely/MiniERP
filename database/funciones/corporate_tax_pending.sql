-- =====================================================================
-- erp.corporate_tax_pending · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0057_corporate_tax   →   la vigente es la de 0057_corporate_tax
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.corporate_tax_pending(p_company uuid, p_origin text, p_source uuid, p_year integer)
 RETURNS numeric
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce(sum(case a.direction when 'increase' then a.amount else -a.amount end), 0)
  from erp.corporate_tax_adjustments a
  join erp.corporate_tax_returns r on r.id = a.return_id and r.status = 'posted'
  join erp.fiscal_years fy on fy.id = r.fiscal_year_id
  where a.company_id = p_company and a.origin = p_origin and a.source_id = p_source and a.included
    and a.kind = 'temporary' and fy.year < p_year;
$function$
;
