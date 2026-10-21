-- =====================================================================
-- PRUEBAS FASE 50 · Practicar integrado: evaluar la IA y glosario (migración 0055)
-- ---------------------------------------------------------------------
--  · Los intentos de la IA guardan el modelo que contestó; los de las personas, no (aunque lo manden).
--  · El progreso enseña la nota, el modelo y la fecha del ÚLTIMO intento de la IA, sin mezclarlo con el del alumno.
--  · submit_exercise rechaza respuestas que no son una lista o que son enormes, y sigue funcionando con 3 argumentos.
--  · Glosario: «Supuesto práctico» y «Catálogo de operaciones».
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'alumno@test.local'),
  ('00000000-0000-0000-0000-0000000000b2', 'otro@test.local');

create or replace function public.falla(sql text, texto text) returns boolean language plpgsql as $$
begin
  execute sql;
  return false;
exception when others then
  if sqlerrm ilike '%' || texto || '%' then return true; end if;
  raise notice 'error inesperado: %', sqlerrm;
  return false;
end $$;
create or replace function public.resp(t text) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('account_no', p[1], 'debit', case p[2] when 'D' then p[3]::numeric else 0 end,
                                      'credit', case p[2] when 'H' then p[3]::numeric else 0 end) order by ord)
  from unnest(string_to_array(t, ' | ')) with ordinality u(x, ord), string_to_array(u.x, ' ') p;
$$;
grant execute on function public.falla(text, text), public.resp(text) to authenticated;

do $$
begin
  assert (select count(*) from erp.concepts where key in ('exercise', 'operationCatalog')) = 2;
  assert (select term from erp.concepts where key = 'operationCatalog') = 'Catálogo de operaciones';
  assert (select count(*) from pg_proc where proname = 'submit_exercise' and pronamespace = 'erp'::regnamespace) = 1, 'una sola versión de submit_exercise';
  raise notice 'OK  · glosario con «Supuesto práctico» y «Catálogo de operaciones»; una sola submit_exercise';
end $$;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare g jsonb;
begin
  -- el alumno: el modelo no se guarda aunque lo mande; con 3 argumentos sigue funcionando
  g := erp.submit_exercise('purchase_vat', public.resp('600 D 2000 | 472 D 420 | 400 H 2420'), 'user', 'trampa');
  assert (g->>'ok')::boolean;
  perform erp.submit_exercise(p_key => 'sale_igic', p_answer => public.resp('430 D 1605 | 700 H 1500 | 477 H 105'), p_by => 'user');
  assert (select count(*) from erp.exercise_attempts where by = 'user' and model is null) = 2, 'los intentos del alumno, sin modelo';

  -- la IA: dos intentos del mismo supuesto, con modelos distintos; el progreso enseña el último
  perform erp.submit_exercise('purchase_vat', public.resp('600 D 2000 | 472 H 420 | 400 H 1580'), 'ai', '@cf/meta/llama-3.3-70b');
  perform pg_sleep(0.01);
  perform erp.submit_exercise('purchase_vat', public.resp('60000001 D 2000 | 47200021 D 420 | 40000001 H 2420'), 'ai', '  @cf/openai/gpt-oss-120b  ');
  assert (select attempts || ' ' || best_score || ' ' || solved || ' · ' || ai_score || ' ' || ai_ok || ' ' || ai_model
          from erp.v_exercise_progress where key = 'purchase_vat') = '1 100 true · 100 true @cf/openai/gpt-oss-120b',
         (select row_to_json(p)::text from erp.v_exercise_progress p where key = 'purchase_vat');
  assert (select ai_at is not null from erp.v_exercise_progress where key = 'purchase_vat');
  assert (select ai_score is null and ai_model is null and attempts = 1 from erp.v_exercise_progress where key = 'sale_igic'), 'sin intento de la IA: vacío';
  assert (select count(*) from erp.v_exercise_progress) = 18;
  raise notice 'OK  · la IA guarda su modelo (sin espacios) y el progreso enseña su último intento; el alumno, sin modelo';

  -- respuestas no válidas
  assert public.falla($q$select erp.submit_exercise('purchase_vat', '{"a": 1}')$q$, 'Invalid answer');
  assert public.falla($q$select erp.submit_exercise('purchase_vat', (select jsonb_agg(jsonb_build_object('account_no', '600', 'debit', 1)) from generate_series(1, 31)))$q$, 'Invalid answer');
  assert public.falla($q$select erp.submit_exercise('purchase_vat', '[]', 'robot')$q$, 'Invalid attempt');
  raise notice 'OK  · se rechazan las respuestas que no son una lista o con más de 30 líneas';
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
begin
  assert (select count(*) from erp.v_exercise_progress where ai_score is not null or attempts > 0) = 0, 'otro usuario no ve la evaluación ajena';
  raise notice 'OK  · cada usuario ve solo su evaluación de la IA';
end $$;

\echo '✔ FASE 50 OK · evaluar la IA y glosario de Practicar'
