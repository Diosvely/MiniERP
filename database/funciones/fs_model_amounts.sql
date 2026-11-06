-- =====================================================================
-- erp.fs_model_amounts · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0089_balance_models   →   la vigente es la de 0089_balance_models
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.fs_model_amounts(p_company uuid, p_year integer, p_model text, p_to_date date DEFAULT NULL::date)
 RETURNS TABLE(code text, amount numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO 'erp', 'public'
AS $function$
  with recursive lines as (select * from erp.fs_model_line_set(p_model)),
  up(code, ancestor) as (
    select l.code, l.code from lines l
    union all
    select up.code, p.parent from up join lines p on p.code = up.ancestor where p.parent is not null
  ), detail as (
    select c.line_code, sum(c.amount) as amount
    from erp.fs_model_classified_at(p_company, p_year, p_model, array[p_to_date]) c
    group by c.line_code
  )
  select up.ancestor, coalesce(sum(d.amount), 0)
  from up left join detail d on d.line_code = up.code
  group by up.ancestor;
$function$
;
