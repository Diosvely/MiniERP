-- =====================================================================
-- erp.grade_exercise · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0054_operations_exercises 0056_grader_fixes   →   la vigente es la de 0056_grader_fixes
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.grade_exercise(p_key text, p_answer jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  x erp.exercises; a jsonb; e jsonb; v_lines jsonb := '[]'; v_ok int := 0; v_n int := 0; v_match numeric; v_other numeric;
  v_used int[] := '{}'; v_extra jsonb := '[]'; v_tips jsonb := '[]'; v_status text; v_debit numeric; v_credit numeric; i int;
  v_alts text[]; v_hits int[]; v_bad jsonb := '[]';
begin
  select * into x from erp.exercises where key = p_key;
  if not found then raise exception 'Exercise % not found', p_key; end if;
  -- la respuesta, normalizada: [{ i, account, side, amount }]
  select coalesce(jsonb_agg(jsonb_build_object('i', o.ord, 'account', btrim(o.v->>'account_no'),
           'problem', erp.pgc_account_problem(btrim(o.v->>'account_no')),
           'side', case when coalesce((o.v->>'debit')::numeric, 0) <> 0 then 'debit' else 'credit' end,
           'amount', abs(coalesce(nullif((o.v->>'debit')::numeric, 0), (o.v->>'credit')::numeric, 0))) order by o.ord), '[]'),
         coalesce(sum(coalesce((o.v->>'debit')::numeric, 0)), 0), coalesce(sum(coalesce((o.v->>'credit')::numeric, 0)), 0)
    into a, v_debit, v_credit
  from jsonb_array_elements(p_answer) with ordinality o(v, ord)
  where coalesce(btrim(o.v->>'account_no'), '') <> '' and (coalesce((o.v->>'debit')::numeric, 0) <> 0 or coalesce((o.v->>'credit')::numeric, 0) <> 0);

  -- v0.40.1 · las cuentas que no son cuentas del PGC (letras, 9999…) no casan con nada: van a «extra» con su motivo
  select coalesce(jsonb_agg(l - 'i' - 'problem' || jsonb_build_object('reason', l->>'problem') order by (l->>'i')::int), '[]') into v_bad
  from jsonb_array_elements(a) l where l->>'problem' is not null;
  select coalesce(jsonb_agg(l), '[]') into a from jsonb_array_elements(a) l where l->>'problem' is null;

  for e in select * from jsonb_array_elements(x.expected) loop
    v_n := v_n + 1;
    v_alts := array[e->>'account'] || coalesce((select array_agg(z) from jsonb_array_elements_text(e->'alt') z), '{}');
    -- líneas de la respuesta de ese grupo y ese lado (que no haya usado otra línea esperada)
    select coalesce(sum((l->>'amount')::numeric), 0), coalesce(array_agg((l->>'i')::int), '{}') into v_match, v_hits
    from jsonb_array_elements(a) l
    where l->>'side' = e->>'side' and exists (select 1 from unnest(v_alts) p where erp.account_matches(l->>'account', p))
      and not ((l->>'i')::int = any (v_used));
    select coalesce(sum((l->>'amount')::numeric), 0) into v_other
    from jsonb_array_elements(a) l
    where l->>'side' <> e->>'side' and exists (select 1 from unnest(v_alts) p where erp.account_matches(l->>'account', p));
    v_status := case when cardinality(v_hits) > 0 and abs(v_match - (e->>'amount')::numeric) < 0.005 then 'ok'
                     when cardinality(v_hits) > 0 then 'amount'
                     when v_other <> 0 then 'side'
                     else 'missing' end;
    if v_status = 'ok' then v_ok := v_ok + 1; end if;
    v_used := v_used || v_hits;
    v_lines := v_lines || jsonb_build_object('account', e->>'account', 'side', e->>'side', 'expected', (e->>'amount')::numeric,
                                             'answered', case when cardinality(v_hits) > 0 then v_match end, 'status', v_status,
                                             'alt_used', cardinality(v_hits) > 0 and not exists (
                                               select 1 from jsonb_array_elements(a) l where (l->>'i')::int = any (v_hits) and erp.account_matches(l->>'account', e->>'account')));
  end loop;
  select coalesce(jsonb_agg(l - 'i' - 'problem'), '[]') || v_bad into v_extra from jsonb_array_elements(a) l where not ((l->>'i')::int = any (v_used));
  -- errores frecuentes reconocidos
  select coalesce(jsonb_agg(jsonb_build_object('msg', r->>'msg', 'msg_en', r->>'msg_en')), '[]') into v_tips
  from jsonb_array_elements(x.errors) r
  where exists (select 1 from jsonb_array_elements(a) l where l->>'side' = r->>'side' and l->>'account' like (r->>'account') || '%');
  -- v0.40.1 · una cuenta de 4 dígitos con otro significado (4009 en lugar de 400): se explica la diferencia
  v_tips := v_tips || coalesce((
    select jsonb_agg(distinct jsonb_build_object('msg', d.tip, 'msg_en', d.tip_en))
    from jsonb_array_elements(a) l
    join erp.pgc_distinct_accounts d on l->>'account' like d.account_no || '%'
    where exists (select 1 from jsonb_array_elements(x.expected) ex
                  where d.account_no like (ex->>'account') || '_%')), '[]');
  return jsonb_build_object('exercise', x.key, 'lines', v_lines, 'extra', v_extra, 'tips', v_tips,
    'balanced', abs(v_debit - v_credit) < 0.005, 'debit', v_debit, 'credit', v_credit,
    'score', case when v_n = 0 then 0 else round(100.0 * v_ok / v_n)::int end,
    'ok', v_ok = v_n and jsonb_array_length(v_extra) = 0 and abs(v_debit - v_credit) < 0.005);
end $function$
;
