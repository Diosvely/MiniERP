-- =====================================================================
-- PRUEBAS FASE 69 · Tableros (migración 0075 · v0.52.0)
-- ---------------------------------------------------------------------
-- Diseño validado por Diosvely (diseno-v0.52.0.md). Con el caso completo «Taller Atlántico SL» (2026 cerrado y 2027
-- abierto) se comprueba que:
--   · cada cifra y cada punto de las series del «Resumen de dirección» coincide con el Balance y la PyG del ERP
--     (financial_statement) a esa fecha, en los 12 fines de mes;
--   · los ingresos y gastos de cada mes suman el resultado acumulado;
--   · el fondo de maniobra y la liquidez al cierre son los de la pantalla Ratios;
--   · con simulación, el tablero es el de después de contabilizar el borrador; sin ella, como siempre;
--   · el catálogo está completo y la web solo lo lee; otra empresa no ve nada.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'owner@test.local'),
                                          ('00000000-0000-0000-0000-0000000000b2', 'otro@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);
create table public.ctx (k text primary key, e uuid);
grant all on public.ctx to authenticated;
create table public.fotos (k text primary key, f jsonb);
grant all on public.fotos to authenticated;
create or replace function public.falla(sql text, texto text) returns boolean language plpgsql as $$
begin
  execute sql;
  return false;
exception when others then
  if sqlerrm ilike '%' || texto || '%' then return true; end if;
  raise notice 'error inesperado: %', sqlerrm;
  return false;
end $$;
grant execute on function public.falla(text, text) to authenticated;

-- Una partida del Balance o de la PyG del ERP a una fecha
create or replace function public.fs(c uuid, y int, st text, code text, d date) returns numeric language sql as $$
  select x.amount from erp.financial_statement(c, y, st, d) x where x.code = $4;
$$;
grant execute on function public.fs(uuid, int, text, text, date) to authenticated;
-- Una métrica de una tarjeta del tablero: { value, prev, series… }
create or replace function public.item(t jsonb, metric text) returns jsonb language sql as $$
  -- la de un gráfico si la hay (lleva las series); si no, la de las cifras clave
  select i from jsonb_array_elements(t -> 'widgets') w, jsonb_array_elements(w -> 'items') i
  where i ->> 'code' = metric order by (w ->> 'kind') = 'kpis' limit 1;
$$;
grant execute on function public.item(jsonb, text) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
begin
  insert into public.ctx values ('c', (erp.create_case_company('taller_atlantico', 'full')->>'company_id')::uuid);
end $$;

-- ---------- El tablero cuadra con el Balance y la PyG ----------
do $$
declare c uuid := (select e from public.ctx where k = 'c'); t jsonb; m date; i int; s numeric; acc numeric := 0;
begin
  t := erp.dashboard_data(c, 'resumen', 2026);
  assert t ->> 'to' = '2026-12-31' and not (t ->> 'has_prev')::boolean, 'sin «hasta», el ejercicio entero; 2025 no existe';
  assert jsonb_array_length(t -> 'months') = 12, '12 fines de mes';
  assert (select count(*) from jsonb_array_elements(t -> 'widgets')) = 5, 'las 5 tarjetas del resumen';
  -- Cifras clave al cierre
  assert (public.item(t, 'SALES') ->> 'value')::numeric = public.fs(c, 2026, 'pyg', 'P1', null), 'cifra de negocios = PyG 1';
  assert (public.item(t, 'RESULT') ->> 'value')::numeric = public.fs(c, 2026, 'pyg', 'PD', null), 'resultado = PyG D';
  assert (public.item(t, 'CASH') ->> 'value')::numeric = public.fs(c, 2026, 'balance', 'AC.VI', null), 'tesorería = efectivo';
  assert (public.item(t, 'WC') ->> 'value')::numeric
       = public.fs(c, 2026, 'balance', 'AC', null) - public.fs(c, 2026, 'balance', 'PC', null), 'fondo de maniobra';
  assert public.item(t, 'SALES') -> 'prev' = 'null'::jsonb, 'sin año anterior, sin comparación';
  -- Igual que la pantalla Ratios al cierre
  assert (public.item(t, 'WC') ->> 'value')::numeric = (select r.value from erp.financial_ratios(c, 2026) r where r.code = 'WC'), 'WC = Ratios';
  assert (public.item(t, 'CR') ->> 'value')::numeric = (select r.value from erp.financial_ratios(c, 2026) r where r.code = 'CR'), 'CR = Ratios';
  assert (public.item(t, 'DEBT') ->> 'value')::numeric = (select r.value from erp.financial_ratios(c, 2026) r where r.code = 'DEBT'), 'DEBT = Ratios';
  assert (public.item(t, 'NPM') ->> 'value')::numeric = (select r.value from erp.financial_ratios(c, 2026) r where r.code = 'NPM'), 'NPM = Ratios';
  assert (public.item(t, 'CR') ->> 'ref_min')::numeric = 1.5, 'la zona de referencia es la de los Ratios';
  raise notice 'OK  · cifras clave y salud financiera = Balance, PyG y Ratios';

  -- Las series, en los 12 fines de mes
  for i in 0..11 loop
    m := (t -> 'months' ->> i)::date;
    assert (public.item(t, 'RESULT') -> 'series' ->> i)::numeric = public.fs(c, 2026, 'pyg', 'PD', m), format('resultado a %s', m);
    assert (public.item(t, 'CASH') -> 'series' ->> i)::numeric = public.fs(c, 2026, 'balance', 'AC.VI', m), format('tesorería a %s', m);
    -- ingresos − gastos de cada mes, acumulados = el resultado a ese fin de mes
    acc := acc + (public.item(t, 'INCOME') -> 'series' ->> i)::numeric - (public.item(t, 'EXPENSES') -> 'series' ->> i)::numeric;
    assert acc = public.fs(c, 2026, 'pyg', 'PD', m), format('ingresos − gastos acumulados a %s', m);
  end loop;
  assert (select sum(x::numeric) from jsonb_array_elements_text(public.item(t, 'INCOME') -> 'series') x)
       = (public.item(t, 'INCOME') ->> 'value')::numeric, 'los ingresos de los 12 meses suman los del año';
  raise notice 'OK  · las series cuadran con el Balance y la PyG en los 12 fines de mes';

  -- 2027 hasta el 30/06, frente a 2026 a la misma fecha
  t := erp.dashboard_data(c, 'resumen', 2027, '2027-06-30');
  insert into public.fotos values ('2027', t);
  assert t ->> 'prev_to' = '2026-06-30' and (t ->> 'has_prev')::boolean;
  assert (public.item(t, 'CASH') ->> 'value')::numeric = public.fs(c, 2027, 'balance', 'AC.VI', '2027-06-30');
  assert (public.item(t, 'CASH') ->> 'prev')::numeric = public.fs(c, 2026, 'balance', 'AC.VI', '2026-06-30'), 'año anterior, a la misma fecha';
  assert (public.item(t, 'RESULT') ->> 'prev')::numeric = public.fs(c, 2026, 'pyg', 'PD', '2026-06-30');
  assert public.item(t, 'CASH') -> 'series' -> 6 = 'null'::jsonb, 'después de «hasta» no hay serie';
  assert (public.item(t, 'CASH') -> 'series' ->> 5)::numeric = public.fs(c, 2027, 'balance', 'AC.VI', '2027-06-30');
  for i in 0..11 loop
    m := (t -> 'months_prev' ->> i)::date;
    assert (public.item(t, 'CASH') -> 'series_prev' ->> i)::numeric = public.fs(c, 2026, 'balance', 'AC.VI', m), format('2026 a %s', m);
  end loop;
  raise notice 'OK  · con «hasta» y el año anterior a la misma fecha';
end $$;

-- ---------- Simulación con un asiento en edición ----------
do $$
declare c uuid := (select e from public.ctx where k = 'c'); a uuid; antes jsonb := (select f from public.fotos where k = '2027');
        s jsonb;
begin
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (c, (select id from erp.fiscal_years where company_id = c and year = 2027), '2027-03-15', 'Seguro (borrador)') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit)
  values (a, (select id from erp.gl_accounts where company_id = c and account_no = '62500001'), 450);
  insert into erp.journal_lines (entry_id, gl_account_id, credit)
  values (a, (select id from erp.gl_accounts where company_id = c and account_no = '57200001'), 450);
  insert into public.ctx values ('borrador', a);

  assert erp.dashboard_data(c, 'resumen', 2027, '2027-06-30') = antes, 'sin simulación, el borrador no cuenta';
  s := erp.dashboard_data(c, 'resumen', 2027, '2027-06-30', true);
  assert (s ->> 'simulation')::boolean;
  assert (public.item(s, 'CASH') ->> 'value')::numeric = (public.item(antes, 'CASH') ->> 'value')::numeric - 450, 'la tesorería baja 450';
  assert (public.item(s, 'EXPENSES') -> 'series' ->> 2)::numeric = (public.item(antes, 'EXPENSES') -> 'series' ->> 2)::numeric + 450,
         'el gasto cae en marzo';
  assert not erp.simulating(), 'al terminar, la simulación se apaga';
  insert into public.fotos values ('sim', s);
  perform erp.post_entry(a);
  assert erp.dashboard_data(c, 'resumen', 2027, '2027-06-30') = s - 'simulation' || '{"simulation": false}',
         'contabilizado, el tablero es el de la simulación';
  raise notice 'OK  · la simulación coincide con el resultado de contabilizar';
end $$;

-- ---------- Errores ----------
do $$
declare c uuid := (select e from public.ctx where k = 'c');
begin
  assert public.falla(format('select erp.dashboard_data(%L, %L, 2027)', c, 'nada'), 'Unknown dashboard');
  assert public.falla(format('select erp.dashboard_data(%L, %L, 2031)', c, 'resumen'), 'No fiscal year');
  assert public.falla('insert into erp.dashboards (code, sort, label, label_en) values (''x'', 1, ''x'', ''x'')', 'permission denied'),
         'la web solo lee el catálogo';
  raise notice 'OK  · errores claros y catálogo de solo lectura';
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
begin
  assert public.falla(format('select erp.dashboard_data(%L, %L, 2027)', (select e from public.ctx where k = 'c'), 'resumen'), 'Not allowed'),
         'otra empresa no ve nada';
  assert (select count(*) from erp.dashboards) = 1, 'el catálogo sí se lee';
  raise notice 'OK  · otra empresa no ve el tablero';
end $$;
reset role;

-- ---------- El catálogo está completo ----------
do $$
begin
  assert not exists (select 1 from erp.dash_widgets w, unnest(w.metrics) m(code)
                     where not exists (select 1 from erp.dash_metrics x where x.code = m.code)), 'cada tarjeta apunta a métricas que existen';
  assert not exists (select 1 from erp.dash_metrics m where m.kind = 'line'
                     and not exists (select 1 from erp.fs_lines l where l.statement = m.statement and l.code = m.line_code)),
         'cada partida existe en el Balance o la PyG';
  assert not exists (select 1 from erp.dash_metrics m join erp.dash_metrics a on a.code in (m.a, m.b) where a.sort >= m.sort),
         'una métrica solo usa métricas que se calculan antes';
  assert not exists (select 1 from erp.dash_widgets w join erp.dashboards d on d.code = w.dashboard
                     where w.kind in ('lines', 'bars') and cardinality(w.metrics) = 0);
  assert not has_function_privilege('anon', 'erp.dashboard_data(uuid, text, integer, date, boolean)', 'execute');
  assert has_function_privilege('authenticated', 'erp.dashboard_data(uuid, text, integer, date, boolean)', 'execute');
  raise notice 'OK  · catálogo completo y permisos';
end $$;

\echo 'FASE 69 OK'
