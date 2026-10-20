-- =====================================================================
-- erp.corporate_tax_loss_carryforwards · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0057_corporate_tax   →   la vigente es la de 0057_corporate_tax
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.corporate_tax_loss_carryforwards(p_company uuid, p_year integer)
 RETURNS TABLE(origin_year integer, generated numeric, used numeric, pending numeric, credit_rate numeric)
 LANGUAGE sql
 STABLE
AS $function$
  with gen as (
    select fy.year::int as y, (r.result->>'loss_generated')::numeric as amount,
           case when (r.result->>'loss_credit')::numeric > 0 then (r.result->>'deferred_rate')::numeric end as rate
    from erp.corporate_tax_returns r join erp.fiscal_years fy on fy.id = r.fiscal_year_id
    where r.company_id = p_company and r.status = 'posted' and fy.year < p_year and (r.result->>'loss_generated')::numeric > 0),
  usage as (
    select (u->>'origin_year')::int as y, sum((u->>'amount')::numeric) as amount
    from erp.corporate_tax_returns r join erp.fiscal_years fy on fy.id = r.fiscal_year_id,
         jsonb_array_elements(coalesce(r.result->'loss_usage', '[]')) u
    where r.company_id = p_company and r.status = 'posted' and fy.year < p_year
    group by 1)
  select g.y, g.amount, coalesce(u.amount, 0), g.amount - coalesce(u.amount, 0), g.rate
  from gen g left join usage u on u.y = g.y
  where g.amount - coalesce(u.amount, 0) > 0
  order by g.y;
$function$
;
