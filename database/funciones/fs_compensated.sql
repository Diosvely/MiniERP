-- =====================================================================
-- erp.fs_compensated · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0096_compensated_balance_and_audits   →   la vigente es la de 0096_compensated_balance_and_audits
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.fs_compensated(p_company uuid, p_year integer, p_to_date date DEFAULT NULL::date, p_drafts boolean DEFAULT false, p_model text DEFAULT 'pymes'::text)
 RETURNS TABLE(code text, parent text, sort integer, level integer, label text, label_en text, is_total boolean, amount numeric, amount_comp numeric)
 LANGUAGE plpgsql
 STABLE
 SET jit TO 'off'
AS $function$
#variable_conflict use_column
declare v_prev text := coalesce(nullif(current_setting('erp.simulate', true), ''), 'off');
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  perform erp.fs_check_model('balance', p_model);
  if p_drafts then perform set_config('erp.simulate', 'on', true); end if;
  return query
  with recursive lines as (select * from erp.fs_model_line_set(p_model)),
  depth(code, level) as (
    select l.code, 0 from lines l where l.parent is null
    union all
    select c.code, d.level + 1 from depth d join lines c on c.parent = d.code
  ),
  up(code, ancestor) as (
    select l.code, l.code from lines l
    union all
    select up.code, p.parent from up join lines p on p.code = up.ancestor where p.parent is not null
  ),
  acc as (select a.account_no, a.balance
          from erp.fs_classified_at(p_company, p_year, 'balance', array[p_to_date]) a),
  pair as (
    select a.account_no, a.balance, m.dl, m.cl
    from acc a
    cross join lateral (
      select x.dl, x.cl from (
        select fm.prefix, fm.debit_line as dl, fm.credit_line as cl from erp.fs_mapping fm
        where p_model = 'pymes' and fm.statement = 'balance' and a.account_no like fm.prefix || '%'
        union all
        select fm.prefix, fm.debit_line, fm.credit_line from erp.fs_model_mapping fm
        where p_model <> 'pymes' and fm.model = p_model and a.account_no like fm.prefix || '%') x
      order by length(x.prefix) desc limit 1) m
  ),
  net as (
    select case when sum(balance) >= 0 then dl else cl end as line, sum(balance) as bal
    from pair group by left(account_no, 2), dl, cl
    having sum(balance) <> 0
  ),
  comp as (
    select n.line as line_code, sum(n.bal * case l.side when 'debit' then 1 else -1 end) as amount
    from net n join lines l on l.code = n.line group by n.line
  ),
  unc as (
    select c.line_code, sum(c.amount) as amount
    from erp.fs_model_classified_at(p_company, p_year, p_model, array[p_to_date]) c group by c.line_code
  ),
  tot as (
    select up.ancestor as code, coalesce(sum(u.amount), 0) as amount, coalesce(sum(k.amount), 0) as amount_comp
    from up
    left join unc u on u.line_code = up.code
    left join comp k on k.line_code = up.code
    group by up.ancestor
  )
  select l.code, l.parent, l.sort, d.level, l.label, l.label_en, l.is_total, t.amount, t.amount_comp
  from lines l join depth d on d.code = l.code join tot t on t.code = l.code
  order by l.sort;
  perform set_config('erp.simulate', v_prev, true);
end $function$
;
