-- =====================================================================
-- erp.global_impairment_calc · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0043_year_end_adjustments   →   la vigente es la de 0043_year_end_adjustments
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.global_impairment_calc(p_company uuid, p_date date, p_rates jsonb)
 RETURNS TABLE(tier text, basis numeric, pct numeric, amount numeric)
 LANGUAGE sql
 STABLE
AS $function$
  with t(tier, sort) as (values ('not_due', 1), ('d1_90', 2), ('d91_180', 3), ('d181_365', 4), ('d365_plus', 5)),
  o as (
    select case when o.days_overdue = 0 then 'not_due' when o.days_overdue <= 90 then 'd1_90'
                when o.days_overdue <= 180 then 'd91_180' when o.days_overdue <= 365 then 'd181_365' else 'd365_plus' end as tier,
           o.pending
    from erp.open_items(p_company, p_date) o
    where o.invoice_type = 'sale' and o.pending > 0
      and not exists (select 1 from erp.receivable_impairments i
                      where i.invoice_id = o.invoice_id and i.status = 'active' and i.impair_date <= p_date)
  )
  select t.tier, coalesce(sum(o.pending), 0), coalesce((p_rates->>t.tier)::numeric, 0),
         round(coalesce(sum(o.pending), 0) * coalesce((p_rates->>t.tier)::numeric, 0) / 100, 2)
  from t left join o on o.tier = t.tier
  group by t.tier, t.sort order by t.sort;
$function$
;
