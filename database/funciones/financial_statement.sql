-- =====================================================================
-- erp.financial_statement · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0016_financial_statements 0032_comparative_statements 0074_report_simulation 0089_balance_models   →   la vigente es la de 0089_balance_models
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.financial_statement(p_company uuid, p_year integer, p_statement text, p_to_date date DEFAULT NULL::date, p_drafts boolean DEFAULT false, p_model text DEFAULT 'pymes'::text)
 RETURNS TABLE(code text, parent text, sort integer, level integer, label text, label_en text, is_total boolean, amount numeric, amount_prev numeric)
 LANGUAGE plpgsql
 STABLE
 SET jit TO 'off'
AS $function$
#variable_conflict use_column
declare v_prev text := coalesce(nullif(current_setting('erp.simulate', true), ''), 'off');
begin
  perform erp.fs_check_model(p_statement, p_model);
  if p_drafts then perform set_config('erp.simulate', 'on', true); end if;
  if p_model = 'pymes' then
    return query
    with recursive depth(code, level) as (
      select l.code, 0 from erp.fs_lines l where l.statement = p_statement and l.parent is null
      union all
      select c.code, d.level + 1 from depth d join erp.fs_lines c on c.statement = p_statement and c.parent = d.code
    )
    select l.code, l.parent, l.sort, d.level, l.label, l.label_en, l.is_total,
           coalesce(n.amount, 0), coalesce(prev.amount, 0)
    from erp.fs_lines l
    join depth d on d.code = l.code
    left join erp.fs_amounts(p_company, p_year, p_statement, p_to_date) n on n.code = l.code
    -- Ejercicio anterior: el Balance, a su cierre (null = completo); la PyG, hasta la misma fecha del año anterior
    left join erp.fs_amounts(p_company, p_year - 1, p_statement,
                             case when p_statement = 'balance' then null
                                  else (p_to_date - interval '1 year')::date end) prev on prev.code = l.code
    where l.statement = p_statement
    order by l.sort;
  else
    return query
    with recursive lines as (select * from erp.fs_model_line_set(p_model)),
    depth(code, level) as (
      select l.code, 0 from lines l where l.parent is null
      union all
      select c.code, d.level + 1 from depth d join lines c on c.parent = d.code
    )
    select l.code, l.parent, l.sort, d.level, l.label, l.label_en, l.is_total,
           coalesce(n.amount, 0), coalesce(prev.amount, 0)
    from lines l
    join depth d on d.code = l.code
    left join erp.fs_model_amounts(p_company, p_year, p_model, p_to_date) n on n.code = l.code
    left join erp.fs_model_amounts(p_company, p_year - 1, p_model, null) prev on prev.code = l.code
    order by l.sort;
  end if;
  perform set_config('erp.simulate', v_prev, true);
end $function$
;
