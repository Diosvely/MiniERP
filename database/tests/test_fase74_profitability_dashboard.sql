-- =====================================================================
-- PRUEBAS FASE 74 · Tablero «Rentabilidad y márgenes» (migración 0080 · v0.53.0)
-- ---------------------------------------------------------------------
-- Diseño validado por Diosvely (plan-tableros.md). Con el caso completo «Taller Atlántico SL» (2026 cerrado y 2027
-- abierto) se comprueba que:
--   · los gastos se ven en positivo: cada uno es su partida de la PyG cambiada de signo (regresión: sin el signo en
--     las métricas de partida, los aprovisionamientos saldrían en negativo y el margen bruto, mayor que las ventas);
--   · margen bruto, EBITDA y resultado de explotación cuadran con la PyG a cada fin de mes;
--   · el EBITDA, el margen de explotación y el margen neto al cierre son los de la pantalla Ratios;
--   · ventas − costes + el resto de partidas de explotación = resultado de explotación (no falta ni sobra nada);
--   · con «hasta» y el año anterior a la misma fecha, y la simulación con un borrador;
--   · el catálogo admite el signo solo en partidas y grupos, y el tablero responde rápido con una empresa grande al lado.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'owner@test.local'),
                                          ('00000000-0000-0000-0000-0000000000b2', 'otro@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000b2', 'member', null)
on conflict (user_id) do nothing;
create table public.ctx (k text primary key, e uuid);
grant all on public.ctx to authenticated;
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

-- Una partida de la PyG del ERP a una fecha
create or replace function public.fs(c uuid, y int, code text, d date) returns numeric language sql as $$
  select coalesce((select x.amount from erp.financial_statement(c, y, 'pyg', d) x where x.code = $3), 0);
$$;
grant execute on function public.fs(uuid, int, text, date) to authenticated;
-- a / b como lo redondea el ERP (4 decimales)
create or replace function public.pct(a numeric, b numeric) returns numeric language sql immutable as $$
  select case when b is null or b = 0 then null else round(a / b, 4) end;
$$;
grant execute on function public.pct(numeric, numeric) to authenticated;
-- Una métrica de una tarjeta: la de un gráfico si la hay (lleva las series); si no, la de las cifras o la tabla
create or replace function public.item(t jsonb, metric text) returns jsonb language sql as $$
  select i from jsonb_array_elements(t -> 'widgets') w, jsonb_array_elements(w -> 'items') i
  where i ->> 'code' = metric order by (w ->> 'kind') in ('kpis', 'table') limit 1;
$$;
grant execute on function public.item(jsonb, text) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
begin
  insert into public.ctx values ('c', (erp.create_case_company('taller_atlantico', 'full')->>'company_id')::uuid);
end $$;
reset role;

-- ---------- Los gastos, en positivo (regresión del signo en las métricas de partida) ----------
do $$
declare c uuid := (select e from public.ctx where k = 'c'); v jsonb;
begin
  select x.v into v from erp.dash_metric_values(c, 2026, array['2026-12-31'::date]) x;
  assert (v ->> 'PROC')::numeric = -public.fs(c, 2026, 'P4', null) and (v ->> 'PROC')::numeric > 0,
         format('aprovisionamientos en positivo: %s', v ->> 'PROC');
  assert (v ->> 'OPEX')::numeric = -public.fs(c, 2026, 'P7', null) and (v ->> 'OPEX')::numeric > 0, 'otros gastos en positivo';
  assert (v ->> 'DEPR')::numeric = -public.fs(c, 2026, 'P8', null) and (v ->> 'DEPR')::numeric > 0, 'amortización en positivo';
  assert (v ->> 'STAFF')::numeric = -public.fs(c, 2026, 'P6', null), 'personal';
  assert (v ->> 'EBIT')::numeric = public.fs(c, 2026, 'PA', null), 'el resultado de explotación, tal cual (sin signo)';
  assert (v ->> 'GROSS')::numeric < (v ->> 'SALES')::numeric, 'el margen bruto es menor que las ventas';
  -- Supuesto: 120.000 de ventas, 37.000 de aprovisionamientos, 4.840 de otros gastos, 3.000 de amortización
  assert (v ->> 'SALES')::numeric = 120000 and (v ->> 'PROC')::numeric = 37000 and (v ->> 'GROSS')::numeric = 83000,
         'margen bruto del caso: 120.000 − 37.000 = 83.000';
  assert (v ->> 'EBITDA')::numeric = 79360, 'EBITDA del caso: 76.360 + 3.000 = 79.360';
  -- Ventas − costes + el resto de partidas de explotación (2, 3, 5, 9 a 12) = resultado de explotación
  assert (v ->> 'SALES')::numeric - (v ->> 'PROC')::numeric - (v ->> 'STAFF')::numeric - (v ->> 'OPEX')::numeric - (v ->> 'DEPR')::numeric
         + (select sum(public.fs(c, 2026, p, null)) from unnest(array['P2', 'P3', 'P5', 'P9', 'P10', 'P11', 'P12']) p)
         = (v ->> 'EBIT')::numeric, 'la estructura de costes no deja nada fuera';
  raise notice 'OK  · los gastos en positivo, y el caso al céntimo (margen bruto 83.000, EBITDA 79.360)';
end $$;

-- ---------- El tablero cuadra con la PyG y con Ratios ----------
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare c uuid := (select e from public.ctx where k = 'c'); t jsonb; m date; i int; s numeric; sales numeric; gross numeric;
        ebitda numeric; prev_s numeric := 0; prev_g numeric := 0;
begin
  t := erp.dashboard_data(c, 'rentabilidad', 2026);
  assert t ->> 'label' = 'Rentabilidad y márgenes';
  assert (select count(*) from jsonb_array_elements(t -> 'widgets')) = 4, 'las 4 tarjetas';
  assert (select jsonb_array_length(w -> 'items') from jsonb_array_elements(t -> 'widgets') w where w ->> 'kind' = 'lines') = 3,
         'tres márgenes en el gráfico de líneas';
  -- Cifras clave al cierre
  assert (public.item(t, 'SALES') ->> 'value')::numeric = public.fs(c, 2026, 'P1', null), 'ventas = PyG 1';
  assert (public.item(t, 'RESULT') ->> 'value')::numeric = public.fs(c, 2026, 'PD', null), 'resultado = PyG D';
  -- Igual que la pantalla Ratios al cierre
  assert (public.item(t, 'EBITDA') ->> 'value')::numeric = (select r.value from erp.financial_ratios(c, 2026) r where r.code = 'EBITDA'),
         'EBITDA = Ratios';
  assert (public.item(t, 'OPM') ->> 'value')::numeric = (select r.value from erp.financial_ratios(c, 2026) r where r.code = 'OPM'),
         'margen de explotación = Ratios';
  assert (public.item(t, 'NPM') ->> 'value')::numeric = (select r.value from erp.financial_ratios(c, 2026) r where r.code = 'NPM'),
         'margen neto = Ratios';
  assert (public.item(t, 'PROC_PCT') ->> 'value')::numeric = public.pct(37000, 120000), 'aprovisionamientos sobre ventas';
  raise notice 'OK  · cifras clave y estructura de costes = PyG y Ratios';

  -- Las series, en los 12 fines de mes
  for i in 0..11 loop
    m := (t -> 'months' ->> i)::date;
    sales := public.fs(c, 2026, 'P1', m);
    gross := sales + public.fs(c, 2026, 'P4', m);                         -- P4 es negativa en la PyG
    ebitda := public.fs(c, 2026, 'PA', m) - public.fs(c, 2026, 'P8', m);
    assert (public.item(t, 'GM_PCT') -> 'series' ->> i)::numeric is not distinct from public.pct(gross, sales), format('margen bruto %% a %s', m);
    assert (public.item(t, 'EBITDA_PCT') -> 'series' ->> i)::numeric is not distinct from public.pct(ebitda, sales), format('margen EBITDA a %s', m);
    assert (public.item(t, 'NPM') -> 'series' ->> i)::numeric is not distinct from public.pct(public.fs(c, 2026, 'PD', m), sales),
           format('margen neto a %s', m);
    -- barras: lo de cada mes = acumulado del mes − el del mes anterior
    assert (public.item(t, 'SALES') -> 'series' ->> i)::numeric = sales - prev_s, format('ventas de %s', m);
    assert (public.item(t, 'GROSS') -> 'series' ->> i)::numeric = gross - prev_g, format('margen bruto de %s', m);
    prev_s := sales; prev_g := gross;
  end loop;
  select sum(x::numeric) into s from jsonb_array_elements_text(public.item(t, 'GROSS') -> 'series') x;
  assert s = 83000, 'el margen bruto de los 12 meses suma el del año';
  raise notice 'OK  · las series cuadran con la PyG en los 12 fines de mes';

  -- 2027 hasta el 30/06, frente a 2026 a la misma fecha
  t := erp.dashboard_data(c, 'rentabilidad', 2027, '2027-06-30');
  assert (t ->> 'has_prev')::boolean and t ->> 'prev_to' = '2026-06-30';
  sales := public.fs(c, 2026, 'P1', '2026-06-30');
  assert (public.item(t, 'GROSS') ->> 'prev')::numeric = sales + public.fs(c, 2026, 'P4', '2026-06-30'), 'margen bruto del año anterior';
  assert public.item(t, 'GM_PCT') -> 'series' -> 6 = 'null'::jsonb, 'después de «hasta» no hay serie';
  for i in 0..11 loop
    m := (t -> 'months_prev' ->> i)::date;
    sales := public.fs(c, 2026, 'P1', m);
    assert (public.item(t, 'GM_PCT') -> 'series_prev' ->> i)::numeric is not distinct from public.pct(sales + public.fs(c, 2026, 'P4', m), sales),
           format('margen bruto de 2026 a %s', m);
  end loop;
  raise notice 'OK  · con «hasta» y el año anterior a la misma fecha';
end $$;

-- ---------- Simulación: una compra en edición baja el margen bruto ----------
do $$
declare c uuid := (select e from public.ctx where k = 'c'); a uuid; antes jsonb; s jsonb;
begin
  antes := erp.dashboard_data(c, 'rentabilidad', 2027, '2027-06-30');
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (c, (select id from erp.fiscal_years where company_id = c and year = 2027), '2027-03-15', 'Compra (borrador)') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit)
  values (a, (select id from erp.gl_accounts where company_id = c and account_no like '600%' and length(account_no) = 8 limit 1), 1000);
  insert into erp.journal_lines (entry_id, gl_account_id, credit)
  values (a, (select id from erp.gl_accounts where company_id = c and account_no = '57200001'), 1000);

  assert erp.dashboard_data(c, 'rentabilidad', 2027, '2027-06-30') = antes, 'sin simulación, el borrador no cuenta';
  s := erp.dashboard_data(c, 'rentabilidad', 2027, '2027-06-30', true);
  assert (public.item(s, 'GROSS') ->> 'value')::numeric = (public.item(antes, 'GROSS') ->> 'value')::numeric - 1000, 'el margen bruto baja 1.000';
  assert (public.item(s, 'EBITDA') ->> 'value')::numeric = (public.item(antes, 'EBITDA') ->> 'value')::numeric - 1000, 'y el EBITDA';
  assert (public.item(s, 'GROSS') -> 'series' ->> 2)::numeric = (public.item(antes, 'GROSS') -> 'series' ->> 2)::numeric - 1000,
         'en marzo';
  assert not erp.simulating(), 'al terminar, la simulación se apaga';
  delete from erp.journal_lines where entry_id = a;
  delete from erp.journal_entries where id = a;
  raise notice 'OK  · la simulación con un borrador';
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
begin
  assert public.falla(format('select erp.dashboard_data(%L, %L, 2027)', (select e from public.ctx where k = 'c'), 'rentabilidad'), 'Not allowed'),
         'otra empresa no ve nada';
  raise notice 'OK  · otra empresa no ve el tablero';
end $$;
reset role;

-- ---------- El catálogo ----------
do $$
begin
  assert public.falla($q$insert into erp.dash_metrics (code, sort, label, label_en, unit, kind, a, b, sign)
                        values ('X', 999, 'x', 'x', 'eur', 'sum', 'SALES', 'PROC', -1)$q$, 'dash_metrics_sign_kind'),
         'una suma no lleva signo';
  assert (select count(*) from erp.dashboards where code in ('resumen', 'rentabilidad')) = 2, 'los dos tableros';
  assert (select sort from erp.dashboards where code = 'rentabilidad') > (select sort from erp.dashboards where code = 'resumen'),
         'el Resumen de dirección sigue el primero';
  assert not exists (select 1 from erp.dash_widgets w, unnest(w.metrics) m(code)
                     where not exists (select 1 from erp.dash_metrics x where x.code = m.code)), 'cada tarjeta apunta a métricas que existen';
  assert not exists (select 1 from erp.dash_metrics m join erp.dash_metrics a on a.code in (m.a, m.b) where a.sort >= m.sort),
         'una métrica solo usa métricas que se calculan antes';
  assert not exists (select 1 from erp.dash_metrics m where m.kind = 'line'
                     and not exists (select 1 from erp.fs_lines l where l.statement = m.statement and l.code = m.line_code)),
         'cada partida existe en la PyG';
  assert (select coalesce('jit=off' = any (p.proconfig), false) from pg_proc p
          where p.oid = 'erp.dash_metric_values(uuid, integer, date[])'::regprocedure), 'sin JIT, como en la 0076';
  raise notice 'OK  · catálogo: signo solo en partidas y grupos';
end $$;

-- ---------- Rápido, aunque al lado haya una empresa grande de otro usuario ----------
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$ begin
  insert into public.ctx values ('grande', (erp.create_case_company('taller_atlantico', 'until_closing')->>'company_id')::uuid);
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', false) \gset
set session_replication_role = replica;
with c as (select e as cid from public.ctx where k = 'grande'),
     fy as (select id from erp.fiscal_years where company_id = (select cid from c) and year = 2026),
     ins as (insert into erp.journal_entries (company_id, fiscal_year_id, entry_no, posting_date, description, status)
             select (select cid from c), (select id from fy), 100000 + g, date '2026-01-01' + (g % 360), 'volumen', 'posted'
             from generate_series(1, 30000) g returning id)
insert into erp.journal_lines (company_id, entry_id, gl_account_id, debit, credit, line_no)
select (select cid from c), i.id, a.id, case when a.account_no = '62300001' then 10 else 0 end,
       case when a.account_no = '57200001' then 10 else 0 end, case when a.account_no = '62300001' then 1 else 2 end
from ins i cross join erp.gl_accounts a where a.company_id = (select cid from c) and a.account_no in ('62300001', '57200001');
set session_replication_role = origin;
analyze erp.journal_entries;
analyze erp.journal_lines;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare c uuid := (select e from public.ctx where k = 'c'); t0 timestamptz; ms numeric;
begin
  t0 := clock_timestamp();
  perform erp.dashboard_data(c, 'rentabilidad', 2027, '2027-06-30');
  ms := extract(epoch from clock_timestamp() - t0) * 1000;
  assert ms < 3000, format('el tablero tarda %s ms', round(ms));
  raise notice 'OK  · el tablero en % ms con una empresa de 30.000 asientos al lado', round(ms);
end $$;
reset role;

\echo 'FASE 74 OK'
