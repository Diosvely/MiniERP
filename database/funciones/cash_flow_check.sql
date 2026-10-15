-- =====================================================================
-- erp.cash_flow_check · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0022_cash_flow   →   la vigente es la de 0022_cash_flow
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.cash_flow_check(p_company uuid, p_year integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare
  v_cash   record;
  v_ind    jsonb;
  v_dir    jsonb;
  v_cross  jsonb;
  v_ctot   jsonb;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  select * into v_cash from erp.cf_cash(p_company, p_year);
  -- totales por actividad: la segunda letra del código (IA3b → A, DB1 → B)
  select jsonb_object_agg(a, s) into v_ind
  from (select substr(line_code, 2, 1) a, sum(amount) s from erp.cf_indirect_detail(p_company, p_year) group by 1) x;
  select jsonb_object_agg(a, s) into v_dir
  from (select substr(line_code, 2, 1) a, sum(amount) s from erp.cf_direct_detail(p_company, p_year) group by 1) x;

  -- Asientos sin dinero (la 57 no varía) con cuentas de actividades distintas
  with cash as (select * from erp.cf_entry_cash(p_company, p_year) where cash <> 0),
  acc as (
    select e.id, l.gl_account_id, -sum(l.debit - l.credit) as amount
    from erp.journal_entries e
    join erp.fiscal_years fy on fy.id = e.fiscal_year_id and fy.year = p_year
    join erp.journal_lines l on l.entry_id = e.id
    where e.company_id = p_company and e.status = 'posted' and e.entry_type = 'normal'
      and e.id not in (select entry_id from cash)
    group by e.id, l.gl_account_id
    having sum(l.debit - l.credit) <> 0),
  mp as (
    select g.id, substr(m.home_line, 2, 1) as act
    from erp.gl_accounts g cross join lateral erp.cf_account_map(g.account_no) m
    where g.id in (select gl_account_id from acc) and g.account_no not like '57%'),
  per_act as (
    select acc.id, mp.act, sum(acc.amount) as amount
    from acc join mp on mp.id = acc.gl_account_id
    group by acc.id, mp.act
    having sum(acc.amount) <> 0)
  select coalesce(jsonb_agg(jsonb_build_object('entry_no', e.entry_no, 'date', e.posting_date,
                    'description', e.description, 'activities', x.acts) order by e.entry_no), '[]'),
         jsonb_build_object('A', coalesce(sum((x.acts->>'A')::numeric), 0), 'B', coalesce(sum((x.acts->>'B')::numeric), 0),
                            'C', coalesce(sum((x.acts->>'C')::numeric), 0))
    into v_cross, v_ctot
  from (select id, jsonb_object_agg(act, amount) as acts from per_act group by id) x
  join erp.journal_entries e on e.id = x.id;

  return jsonb_build_object(
    'year', p_year,
    'cash_opening', v_cash.opening, 'cash_closing', v_cash.closing, 'cash_change', v_cash.closing - v_cash.opening,
    'indirect', jsonb_build_object('A', coalesce((v_ind->>'A')::numeric, 0), 'B', coalesce((v_ind->>'B')::numeric, 0),
                                   'C', coalesce((v_ind->>'C')::numeric, 0),
                                   'total', coalesce((select sum(value::numeric) from jsonb_each_text(v_ind)), 0)),
    'direct', jsonb_build_object('A', coalesce((v_dir->>'A')::numeric, 0), 'B', coalesce((v_dir->>'B')::numeric, 0),
                                 'C', coalesce((v_dir->>'C')::numeric, 0),
                                 'total', coalesce((select sum(value::numeric) from jsonb_each_text(v_dir)), 0)),
    'balanced', coalesce((select sum(value::numeric) from jsonb_each_text(v_ind)), 0) = v_cash.closing - v_cash.opening
            and coalesce((select sum(value::numeric) from jsonb_each_text(v_dir)), 0) = v_cash.closing - v_cash.opening,
    'cross_entries', (select coalesce(jsonb_agg(x), '[]') from (select x from jsonb_array_elements(v_cross) x limit 20) s),
    'cross_count', jsonb_array_length(v_cross),
    -- lo que esos asientos explican: indirecto − directo en cada actividad
    'cross_total', v_ctot);
end $function$
;
