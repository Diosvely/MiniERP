-- =====================================================================
-- erp.dash_ranking_card · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0083_sales_expenses_dashboard 0084_quality_dashboard   →   la vigente es la de 0084_quality_dashboard
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.dash_ranking_card(p_company uuid, p_year integer, p_to date, p_prev_to date, p_has_prev boolean, p_source text, p_top integer, p_sales numeric, p_sales_prev numeric)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  with cur as (select * from erp.dash_ranking(p_company, p_year, p_to, p_source)),
       prv as (select * from erp.dash_ranking(p_company, p_year - 1, p_prev_to, p_source) where p_has_prev),
       ranked as (select c.*, row_number() over (order by c.amount desc, c.key) as n from cur c where c.key is not null),
       top as (select r.*, (select p.amount from prv p where p.key = r.key) as prev from ranked r where r.n <= p_top)
  select jsonb_build_object(
    'source', p_source,
    'base', case p_source when 'expense_groups' then 'sales' when 'anomalies' then 'none' else 'total' end,
    'rows', coalesce((select jsonb_agg(jsonb_build_object('key', key, 'label', label, 'value', amount, 'prev', prev, 'note', note, 'note_en', note_en) order by n) from top), '[]'),
    'rest', jsonb_build_object(
      'count', (select count(*) from ranked where n > p_top),
      'value', (select coalesce(sum(amount), 0) from ranked where n > p_top),
      'prev', case when p_has_prev then (select coalesce(sum(p.amount), 0) from prv p
                                         where p.key is not null and p.key not in (select key from top)) end),
    'none', jsonb_build_object(
      'value', (select coalesce(sum(amount), 0) from cur where key is null),
      'prev', case when p_has_prev then (select coalesce(sum(amount), 0) from prv where key is null) end),
    'total', jsonb_build_object(
      'value', (select coalesce(sum(amount), 0) from cur),
      'prev', case when p_has_prev then (select coalesce(sum(amount), 0) from prv) end),
    'sales', jsonb_build_object('value', p_sales, 'prev', p_sales_prev));
$function$
;
