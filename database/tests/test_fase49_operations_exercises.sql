-- =====================================================================
-- PRUEBAS FASE 49 · Catálogo de operaciones y supuestos autocorregidos (migración 0054)
-- ---------------------------------------------------------------------
--  · Catálogo: 17 operaciones con su pantalla, su asiento modelo y sus fuentes; un asiento dice a qué operación se parece.
--  · Supuestos: 14, todos con el asiento esperado cuadrado, su explicación, sus fuentes y su concepto del glosario.
--    Cada uno, contestado bien con subcuentas de 8 dígitos, saca un 100.
--  · Corrección: lado cambiado, cuenta equivocada (410 en vez de 400), importe mal, asiento descuadrado, cuenta
--    alternativa (700 en vez de 708), líneas partidas (dos líneas a la 476) y los errores frecuentes explicados.
--  · Intentos: cada usuario ve los suyos y su progreso; los de la IA aparte.
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
-- respuesta en jsonb desde texto: '600 D 2000 | 472 D 420 | 400 H 2420'
create or replace function public.resp(t text) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('account_no', p[1], 'debit', case p[2] when 'D' then p[3]::numeric else 0 end,
                                      'credit', case p[2] when 'H' then p[3]::numeric else 0 end) order by ord)
  from unnest(string_to_array(t, ' | ')) with ordinality u(x, ord), string_to_array(u.x, ' ') p;
$$;
grant execute on function public.falla(text, text), public.resp(text) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare g jsonb; x record; ans jsonb;
begin
  -- ---------- 1. Catálogo ----------
  assert (select count(*) from erp.operations) = 17 and (select count(*) from erp.exercises) = 14;
  assert not exists (select 1 from erp.operations o, unnest(o.sources) k where not exists (select 1 from erp.sources s where s.key = k))
     and not exists (select 1 from erp.exercises o, unnest(o.sources) k where not exists (select 1 from erp.sources s where s.key = k)),
         'todas las fuentes citadas existen en la base documental';
  assert (select count(*) from erp.sources) = 16, 'diez fuentes de la v0.39.0 + seis de los supuestos';
  assert not exists (select 1 from erp.exercises where cardinality(sources) = 0 or concept is null), 'cada supuesto cita su norma y su concepto';
  assert not exists (select 1 from erp.exercises xx where (select sum((e->>'amount')::numeric) filter (where e->>'side' = 'debit') from jsonb_array_elements(xx.expected) e)
                                                    <> (select sum((e->>'amount')::numeric) filter (where e->>'side' = 'credit') from jsonb_array_elements(xx.expected) e)),
         'todos los asientos esperados cuadran';
  raise notice 'OK  · 17 operaciones y 14 supuestos, con fuentes y concepto; los asientos esperados cuadran';

  -- ---------- 2. ¿Dónde se registra? ----------
  assert (select key from erp.operation_for_lines(public.resp('60000001 D 100 | 47200021 D 21 | 40000001 H 121'))) = 'purchase_invoice';
  assert (select key from erp.operation_for_lines(public.resp('60000001 D 100 | 47208021 D 21 | 47708021 H 21 | 40000002 H 100'))) = 'intra_eu_acquisition', 'la más concreta gana';
  assert (select key || ' ' || screen from erp.operation_for_lines(public.resp('64000001 D 2000 | 64200001 D 640 | 47600001 H 770 | 47510001 H 240 | 46500001 H 1630'))) = 'payroll payroll';
  assert (select key from erp.operation_for_lines(public.resp('47700021 D 2982 | 47200021 H 2793 | 47500001 H 189'))) = 'tax_settlement';
  assert (select key || ' ' || screen from erp.operation_for_lines(public.resp('57200001 D 1000 | 43000001 H 1000'))) = 'collection payments';
  assert (select key || ' ' || screen from erp.operation_for_lines(public.resp('68100001 D 1200 | 28130001 H 1200'))) = 'depreciation assets';
  assert not exists (select 1 from erp.operation_for_lines(public.resp('62600001 D 10 | 57200001 H 10'))), 'un gasto bancario no tiene módulo';
  raise notice 'OK  · el asiento propuesto dice su operación y su pantalla (compra, AIB, nómina, liquidación, cobro, amortización)';

  -- ---------- 3. Cada supuesto, bien contestado con subcuentas ----------
  for x in select * from erp.exercises loop
    select jsonb_agg(jsonb_build_object('account_no', rpad(e->>'account', 7, '0') || '1',
             'debit', case e->>'side' when 'debit' then (e->>'amount')::numeric else 0 end,
             'credit', case e->>'side' when 'credit' then (e->>'amount')::numeric else 0 end)) into ans
    from jsonb_array_elements(x.expected) e;
    g := erp.grade_exercise(x.key, ans);
    assert (g->>'ok')::boolean and (g->>'score')::int = 100, x.key || ': ' || g::text;
  end loop;
  raise notice 'OK  · los 14 supuestos, contestados bien con subcuentas de 8 dígitos, sacan un 100';

  -- ---------- 4. Corrección ----------
  g := erp.grade_exercise('purchase_vat', public.resp('600 D 2000 | 472 H 420 | 400 H 2420'));
  assert not (g->>'ok')::boolean and g->'lines'->1->>'status' = 'side' and (g->>'balanced')::boolean = false
     and g->'tips'->0->>'msg' like 'El IVA soportado va al Debe%' and (g->>'score')::int = 67, g::text;
  g := erp.grade_exercise('purchase_vat', public.resp('600 D 2000 | 472 D 420 | 410 H 2420'));
  assert g->'lines'->2->>'status' = 'missing' and g->'extra'->0->>'account' = '410' and g->'tips'->0->>'msg' like 'Los proveedores de mercaderías van a la 400%', g::text;
  g := erp.grade_exercise('purchase_vat', public.resp('600 D 2000 | 472 D 400 | 400 H 2400'));
  assert g->'lines'->1->>'status' = 'amount' and (g->'lines'->1->>'answered')::numeric = 400 and (g->>'balanced')::boolean, g::text;
  raise notice 'OK  · lado cambiado (con su explicación), cuenta equivocada (410: falta la 400 y sobra la 410) e importe mal';
  g := erp.grade_exercise('credit_memo_sale', public.resp('70000001 D 500 | 47700021 D 105 | 43000001 H 605'));
  assert (g->>'ok')::boolean and (g->'lines'->0->>'alt_used')::boolean, 'la 700 también vale (avisando de la 708): ' || g::text;
  g := erp.grade_exercise('monthly_payroll', public.resp('640 D 2000 | 642 D 640 | 476 H 130 | 476 H 640 | 4751 H 240 | 465 H 1630'));
  assert (g->>'ok')::boolean, 'dos líneas a la 476 suman 770: ' || g::text;
  g := erp.grade_exercise('monthly_payroll', public.resp('640 D 2000 | 642 D 640 | 476 H 770 | 4751 H 240 | 572 H 1630'));
  assert not (g->>'ok')::boolean and g->'tips'->0->>'msg' like 'El líquido aún no se ha pagado%', g::text;
  g := erp.grade_exercise('inventory_change', public.resp('610 D 8000 | 300 H 8000 | 300 D 6000 | 610 H 6000'));
  assert (g->>'ok')::boolean, 'la misma cuenta a los dos lados';
  g := erp.grade_exercise('inventory_change', public.resp('610 D 2000 | 300 H 2000'));
  assert not (g->>'ok')::boolean and (g->>'score')::int = 0, 'el neto no vale: hay que dar de baja la inicial y de alta la final';
  g := erp.grade_exercise('year_end_result', public.resp('70000001 D 65000 | 62900001 H 50000 | 12900001 H 15000'));
  assert (g->>'ok')::boolean, 'grupos 6 y 7 por el primer dígito';
  assert public.falla($q$select erp.grade_exercise('no_existe', '[]')$q$, 'not found');
  raise notice 'OK  · cuenta alternativa (700 por 708), líneas partidas, misma cuenta a los dos lados y grupos 6 / 7';

  -- ---------- 5. Intentos y progreso ----------
  perform erp.submit_exercise('purchase_vat', public.resp('600 D 2000 | 472 H 420 | 400 H 2420'));
  perform erp.submit_exercise('purchase_vat', public.resp('600 D 2000 | 472 D 420 | 400 H 2420'));
  perform erp.submit_exercise('sale_igic', public.resp('430 D 1605 | 700 H 1605'), 'ai');
  assert (select attempts || ' ' || best_score || ' ' || solved from erp.v_exercise_progress where key = 'purchase_vat') = '2 100 true';
  assert (select attempts || ' ' || coalesce(ai_score, -1) || ' ' || coalesce(ai_ok::text, '-') from erp.v_exercise_progress where key = 'sale_igic') = '0 33 false',
         (select attempts || ' ' || coalesce(ai_score, -1) || ' ' || coalesce(ai_ok::text, '-') from erp.v_exercise_progress where key = 'sale_igic');
  assert (select count(*) from erp.v_exercise_progress) = 14;
  assert public.falla($q$select erp.submit_exercise('purchase_vat', '[]', 'otro')$q$, 'Invalid attempt');
  raise notice 'OK  · intentos guardados: dos del alumno (mejor nota 100, resuelto) y uno de la IA (33), aparte';
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
begin
  assert (select count(*) from erp.exercise_attempts) = 0, 'otro usuario no ve los intentos ajenos';
  assert (select sum(attempts) from erp.v_exercise_progress) = 0;
  assert (select count(*) from erp.exercises) = 14, 'pero sí los supuestos';
  raise notice 'OK  · cada usuario ve solo sus intentos';
end $$;
select set_config('request.jwt.claim.sub', '', false) \gset
do $$
begin
  assert public.falla($q$select erp.submit_exercise('purchase_vat', '[]')$q$, 'Sign in'), 'sin sesión no se guarda';
  raise notice 'OK  · sin sesión no se guardan intentos';
end $$;

\echo '✔ FASE 49 OK · catálogo de operaciones y supuestos autocorregidos'
