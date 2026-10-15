-- =====================================================================
-- erp.cash_flow_statement · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0022_cash_flow   →   la vigente es la de 0022_cash_flow
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.cash_flow_statement(p_company uuid, p_year integer, p_method text)
 RETURNS TABLE(code text, parent text, sort integer, level integer, label text, label_en text, is_total boolean, amount numeric, amount_prev numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  if p_method not in ('indirect', 'direct') then raise exception 'Unknown cash flow method: %', p_method; end if;
  return query
  with recursive depth(code, level) as (
    select l.code, 0 from erp.cf_lines l where l.method = p_method and l.parent is null
    union all
    select c.code, d.level + 1 from depth d join erp.cf_lines c on c.method = p_method and c.parent = d.code
  ), up(code, ancestor) as (
    select l.code, l.code from erp.cf_lines l where l.method = p_method
    union all
    select up.code, p.parent from up join erp.cf_lines p on p.method = p_method and p.code = up.ancestor
    where p.parent is not null
  ), det as (
    select x.line_code, sum(x.amount) as amount, 0 as y from erp.cf_detail(p_company, p_year, p_method) x group by 1
    union all
    select x.line_code, sum(x.amount), 1 from erp.cf_detail(p_company, p_year - 1, p_method) x group by 1
  ), tot as (
    select up.ancestor as code,
           coalesce(sum(d.amount) filter (where d.y = 0), 0) as amount,
           coalesce(sum(d.amount) filter (where d.y = 1), 0) as amount_prev
    from up left join det d on d.line_code = up.code
    group by up.ancestor)
  select l.code, l.parent, l.sort, d.level, l.label, l.label_en, l.is_total, t.amount, t.amount_prev
  from erp.cf_lines l
  join depth d on d.code = l.code
  join tot t on t.code = l.code
  where l.method = p_method
  order by l.sort;
end $function$
;
