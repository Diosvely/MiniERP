-- =====================================================================
-- PRUEBAS FASE 51 · Corrector de supuestos: solo cuentas válidas del PGC (migración 0056 · v0.40.1)
-- ---------------------------------------------------------------------
-- Regresión de la revisión externa del 19-10-2026: erp.grade_exercise aceptaba cualquier cuenta que EMPEZARA por la
-- esperada. Daba por buena la 4009 (facturas pendientes de recibir) en lugar de la 400, y cuentas que no existen
-- (600xyz, 400ABC). Esta prueba falla con la 0054 / 0055 y pasa con la 0056.
--  · Formato: solo dígitos. Existencia: hasta 3 dígitos, cuenta del PGC; con más, su cuenta de 3 dígitos del PGC.
--  · Cuentas de 4 dígitos con otro significado (4009, 4109, 4309, 4409): no casan con su madre, y se explica por qué.
--  · No se rompe nada: las 14 soluciones (con subcuentas y con sus alternativas) siguen sacando un 100, y todas las
--    subcuentas que crea el propio ERP (impuestos de IVA e IGIC, terceros, bancos) siguen valiendo.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);

create or replace function public.resp(t text) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('account_no', p[1], 'debit', case p[2] when 'D' then p[3]::numeric else 0 end,
                                      'credit', case p[2] when 'H' then p[3]::numeric else 0 end) order by ord)
  from unnest(string_to_array(t, ' | ')) with ordinality u(x, ord), string_to_array(u.x, ' ') p;
$$;
create or replace function public.linea(g jsonb, cuenta text) returns jsonb language sql as $$
  select l from jsonb_array_elements(g->'lines') l where l->>'account' = cuenta limit 1;
$$;
grant execute on function public.resp(text), public.linea(jsonb, text) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare g jsonb;
begin
  -- ---------- 1. El fallo: la 4009 no es la 400 ----------
  g := erp.grade_exercise('purchase_vat', public.resp('600 D 2000 | 472 D 420 | 4009 H 2420'));
  assert not (g->>'ok')::boolean, '4009 en lugar de 400 no puede salir bien: ' || g::text;
  assert public.linea(g, '400')->>'status' = 'missing', 'la 400 falta: ' || g::text;
  assert exists (select 1 from jsonb_array_elements(g->'tips') t where t->>'msg' like 'La 4009 es para facturas pendientes de recibir%'),
         'con la pista de la 4009: ' || g::text;
  g := erp.grade_exercise('purchase_vat', public.resp('60000001 D 2000 | 47200021 D 420 | 40090001 H 2420'));
  assert not (g->>'ok')::boolean and public.linea(g, '400')->>'status' = 'missing', 'tampoco una subcuenta de la 4009: ' || g::text;
  g := erp.grade_exercise('sale_igic', public.resp('4309 D 1605 | 700 H 1500 | 477 H 105'));
  assert not (g->>'ok')::boolean and exists (select 1 from jsonb_array_elements(g->'tips') t where t->>'msg' like 'La 4309%'), g::text;
  raise notice 'OK  · la 4009 (y la 40090001) no valen por la 400, ni la 4309 por la 430, y se explica por qué';

  -- ---------- 2. Cuentas que no son cuentas ----------
  g := erp.grade_exercise('purchase_vat', public.resp('600xyz D 2000 | 472 D 420 | 400ABC H 2420'));
  assert not (g->>'ok')::boolean, '600xyz / 400ABC no valen: ' || g::text;
  assert (select count(*) from jsonb_array_elements(g->'extra') x where x->>'reason' = 'invalid') = 2, 'dos cuentas no válidas: ' || g::text;
  g := erp.grade_exercise('purchase_vat', public.resp('600 D 2000 | 472 D 420 | 9999 H 2420'));
  assert not (g->>'ok')::boolean and exists (select 1 from jsonb_array_elements(g->'extra') x where x->>'account' = '9999' and x->>'reason' = 'not_in_pgc'),
         '9999 no existe en el PGC: ' || g::text;
  g := erp.grade_exercise('purchase_vat', public.resp('600 D 2000 | 472 D 420 | 40 H 2420'));
  assert not (g->>'ok')::boolean, 'el subgrupo 40 no es la cuenta 400: ' || g::text;
  g := erp.grade_exercise('purchase_vat', public.resp('600 D 2000 | 472 D 420 | 999 H 2420'));
  assert exists (select 1 from jsonb_array_elements(g->'extra') x where x->>'account' = '999' and x->>'reason' = 'not_in_pgc'), g::text;
  raise notice 'OK  · 600xyz, 400ABC (no válidas), 9999 y 999 (no existen) y el subgrupo 40 no valen, con su motivo';

  -- ---------- 3. Lo que funcionaba sigue funcionando ----------
  g := erp.grade_exercise('purchase_vat', public.resp('60000001 D 2000 | 47200021 D 420 | 40000001 H 2420'));
  assert (g->>'ok')::boolean and (g->>'score')::int = 100, g::text;
  g := erp.grade_exercise('purchase_vat', public.resp('600 D 2000 | 472 D 420 | 400 H 2420'));
  assert (g->>'ok')::boolean and jsonb_array_length(g->'tips') = 0, g::text;
  g := erp.grade_exercise('purchase_vat', public.resp('4000 D 1 | 600 D 2000 | 472 D 420 | 400 H 2421'));
  assert exists (select 1 from jsonb_array_elements(g->'extra') x where x->>'account' = '4000' and x->>'reason' is null),
         'la 4000 (Proveedores, euros) es una cuenta válida: sobra, pero no por inválida: ' || g::text;
  g := erp.grade_exercise('purchase_vat', public.resp('600 D 2000 | 472 D 420 | 400 H 2000'));
  assert not (g->>'ok')::boolean and not (g->>'balanced')::boolean, 'descuadrado con cuentas buenas: mal';
  g := erp.grade_exercise('year_end_result', public.resp('70000001 D 65000 | 62900001 H 50000 | 12900001 H 15000'));
  assert (g->>'ok')::boolean, 'los grupos 6 y 7 siguen casando por su primer dígito: ' || g::text;
  g := erp.grade_exercise('professional_withholding', public.resp('62300001 D 1000 | 47200021 D 210 | 47510001 H 150 | 41000001 H 1060'));
  assert (g->>'ok')::boolean, 'cuenta esperada de 4 dígitos (4751): ' || g::text;
  raise notice 'OK  · subcuentas, cuentas de 3 dígitos, la 4000, grupos 6 / 7 y la 4751 siguen bien; descuadrado, mal';
end $$;

-- ---------- 4. Las 14 soluciones, con subcuentas y con cada alternativa ----------
do $$
declare x record; g jsonb; ans jsonb; n int := 0;
begin
  for x in select * from erp.exercises loop
    select jsonb_agg(jsonb_build_object('account_no', rpad(e->>'account', 7, '0') || '1',
             'debit', case e->>'side' when 'debit' then (e->>'amount')::numeric else 0 end,
             'credit', case e->>'side' when 'credit' then (e->>'amount')::numeric else 0 end)) into ans
    from jsonb_array_elements(x.expected) e;
    g := erp.grade_exercise(x.key, ans);
    assert (g->>'ok')::boolean and (g->>'score')::int = 100, x.key || ': ' || g::text;
    -- con las alternativas permitidas
    if exists (select 1 from jsonb_array_elements(x.expected) e where e ? 'alt') then
      select jsonb_agg(jsonb_build_object('account_no', rpad(coalesce(e->'alt'->>0, e->>'account'), 7, '0') || '1',
               'debit', case e->>'side' when 'debit' then (e->>'amount')::numeric else 0 end,
               'credit', case e->>'side' when 'credit' then (e->>'amount')::numeric else 0 end)) into ans
      from jsonb_array_elements(x.expected) e;
      g := erp.grade_exercise(x.key, ans);
      assert (g->>'ok')::boolean and exists (select 1 from jsonb_array_elements(g->'lines') l where (l->>'alt_used')::boolean),
             x.key || ' con su alternativa: ' || g::text;
      n := n + 1;
    end if;
  end loop;
  assert n >= 1;
  raise notice 'OK  · las 14 soluciones sacan un 100 con subcuentas, y con sus alternativas (% supuestos), avisando', n;
end $$;

-- ---------- 5. Las subcuentas que crea el propio ERP siguen valiendo ----------
reset role;
do $$
declare e1 uuid; e2 uuid; r record; n int := 0;
begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);
  insert into erp.companies (name, industry, tax_territory, created_by) values ('Península SL', 'retail', 'mainland', auth.uid()) returning id into e1;
  insert into erp.companies (name, industry, tax_territory, created_by) values ('Canarias SL', 'services', 'canary_islands', auth.uid()) returning id into e2;
  perform erp.create_fiscal_year(e1, 2026); perform erp.create_fiscal_year(e2, 2026);
  perform erp.setup_taxes(e1); perform erp.setup_taxes(e2);
  perform erp.create_partner(e1, 'vendor', 'Proveedor SL', 'B11111119'); perform erp.create_partner(e1, 'creditor', 'Ana Ruiz', '12345678Z');
  perform erp.create_partner(e2, 'customer', 'Cliente SL', 'A58818501'); perform erp.create_partner(e2, 'debtor', 'Deudor SL', 'B87654323');
  perform erp.create_posting_account(e1, '57200001', 'Banco');
  for r in select account_no from erp.gl_accounts where company_id in (e1, e2) and account_type = 'posting' loop
    assert erp.pgc_account_problem(r.account_no) is null, 'subcuenta del ERP rechazada: ' || r.account_no;
    assert erp.account_matches(r.account_no, left(r.account_no, 3)), 'subcuenta del ERP que no casa con su cuenta: ' || r.account_no;
    n := n + 1;
  end loop;
  assert n >= 20, 'subcuentas comprobadas: ' || n;
  raise notice 'OK  · las % subcuentas que crea el ERP (IVA, IGIC, ISP, recargo, terceros, banco) son válidas y casan con su cuenta', n;
end $$;

\echo '✔ FASE 51 OK · el corrector solo admite cuentas válidas del PGC'
