-- =====================================================================
-- erp.cash_flow_check · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0022_cash_flow 0066_complete_case 0074_report_simulation   →   la vigente es la de 0074_report_simulation
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.cash_flow_check(p_company uuid, p_year integer, p_drafts boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  v_prev   text := coalesce(nullif(current_setting('erp.simulate', true), ''), 'off');
  v_cash   record;
  v_ind    jsonb;
  v_dir    jsonb;
  v_cross  jsonb;
  v_ctot   jsonb;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  if p_drafts then perform set_config('erp.simulate', 'on', true); end if;
  select * into v_cash from erp.cf_cash(p_company, p_year);
  -- totales por actividad: la segunda letra del código (IA3b → A, DB1 → B)
  select jsonb_object_agg(a, s) into v_ind
  from (select substr(line_code, 2, 1) a, sum(amount) s from erp.cf_indirect_detail(p_company, p_year) group by 1) x;
  select jsonb_object_agg(a, s) into v_dir
  from (select substr(line_code, 2, 1) a, sum(amount) s from erp.cf_direct_detail(p_company, p_year) group by 1) x;

  -- Asientos sin dinero (la 57 no varía) con cuentas de actividades distintas
  with per_act as (
    select f.entry_id as id, substr(f.home_line, 2, 1) as act, sum(f.flow) as amount
    from erp.cf_line_flows(p_company, p_year) f
    where f.entry_id not in (select ce.entry_id from erp.cf_entry_cash(p_company, p_year) ce where ce.cash <> 0)
    group by 1, 2
    having sum(f.flow) <> 0)
  select coalesce(jsonb_agg(jsonb_build_object('entry_no', e.entry_no, 'date', e.posting_date,
                    'description', e.description, 'activities', x.acts) order by e.entry_no), '[]'),
         jsonb_build_object('A', coalesce(sum((x.acts->>'A')::numeric), 0), 'B', coalesce(sum((x.acts->>'B')::numeric), 0),
                            'C', coalesce(sum((x.acts->>'C')::numeric), 0))
    into v_cross, v_ctot
  from (select id, jsonb_object_agg(act, amount) as acts from per_act group by id) x
  join erp.journal_entries e on e.id = x.id;
  perform set_config('erp.simulate', v_prev, true);

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
