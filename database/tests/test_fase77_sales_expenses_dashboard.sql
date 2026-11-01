-- =====================================================================
-- PRUEBAS FASE 77 · Tablero «Ventas y gastos» (migración 0083 · v0.56.0)
-- ---------------------------------------------------------------------
-- Diseño validado por Diosvely (diseno-v0.56.0.md). Con el caso completo «Taller Atlántico SL» se comprueba que:
--   · el ranking de clientes suma la cifra de negocios y el de gastos por naturaleza, el grupo 6; el caso, al céntimo
--     (Cliente General SL 118.000 €, Cliente Dudoso SL 2.000 €; Recambios Canarios SL 45.000 € y la inversión de
--     Maquinaria Atlántica SL, 40.000 €, sin IGIC);
--   · un asiento con dos clientes se reparte en proporción, un cobro no cuenta (regresión: si contara lo que se carga
--     en la cuenta del cliente, el cliente «vendería» dos veces) y una rectificativa resta;
--   · los N primeros y el «Resto», «hasta» con el año anterior, la simulación, otra empresa no ve nada y rapidez con
--     una empresa grande al lado.
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

-- Una partida del Balance o de la PyG del ERP a una fecha
create or replace function public.fs(c uuid, y int, st text, code text, d date) returns numeric language sql as $$
  select coalesce((select x.amount from erp.financial_statement(c, y, st, d) x where x.code = $4), 0);
$$;
grant execute on function public.fs(uuid, int, text, text, date) to authenticated;
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
-- La tarjeta de ranking de una fuente
create or replace function public.rk(t jsonb, src text) returns jsonb language sql as $$
  select w -> 'ranking' from jsonb_array_elements(t -> 'widgets') w where w ->> 'source' = src;
$$;
grant execute on function public.rk(jsonb, text) to authenticated;
-- El importe de una subcuenta en un ranking (null si no está entre los primeros)
create or replace function public.rv(r jsonb, k text) returns numeric language sql as $$
  select (x ->> 'value')::numeric from jsonb_array_elements(r -> 'rows') x where x ->> 'key' = k;
$$;
grant execute on function public.rv(jsonb, text) to authenticated;
-- Lo que suma un ranking: sus filas, el resto y lo que no tiene tercero
create or replace function public.rsum(r jsonb) returns numeric language sql as $$
  select coalesce((select sum((x ->> 'value')::numeric) from jsonb_array_elements(r -> 'rows') x), 0)
         + (r -> 'rest' ->> 'value')::numeric + (r -> 'none' ->> 'value')::numeric;
$$;
grant execute on function public.rsum(jsonb) to authenticated;

-- ---------- Los rankings cuadran con la PyG ----------
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare c uuid := (select e from public.ctx where k = 'c'); t jsonb; r jsonb;
begin
  t := erp.dashboard_data(c, 'ventas', 2026);
  assert t ->> 'label' = 'Ventas y gastos';
  assert (select count(*) from jsonb_array_elements(t -> 'widgets')) = 6, 'las 6 tarjetas';
  -- Clientes: su total (con el resto y «sin cliente») = la cifra de negocios
  r := public.rk(t, 'customers');
  assert public.rsum(r) = public.fs(c, 2026, 'pyg', 'P1', null) and (r -> 'total' ->> 'value')::numeric = public.rsum(r),
         format('clientes = cifra de negocios: %s', public.rsum(r));
  assert public.rv(r, '43000001') = 118000 and public.rv(r, '43000002') = 2000, 'caso: 118.000 y 2.000 sin IGIC';
  assert r -> 'rows' -> 0 ->> 'label' = 'Cliente General SL', 'ordenados de mayor a menor';
  assert r ->> 'base' = 'total';
  -- Proveedores: compras (Recambios Canarios) e inversión en el torno (Maquinaria Atlántica, grupo 2)
  r := public.rk(t, 'suppliers');
  assert public.rv(r, '40000001') = 45000 and public.rv(r, '40000002') = 40000, 'compras e inversión sin IGIC';
  assert public.rsum(r) = (r -> 'total' ->> 'value')::numeric;
  -- Gastos por naturaleza: su total = el grupo 6 (la métrica «Gastos» del Resumen de dirección)
  r := public.rk(t, 'expense_groups');
  assert (r -> 'total' ->> 'value')::numeric = (select (x.v ->> 'EXPENSES')::numeric from erp.dash_metric_values(c, 2026, array['2026-12-31'::date]) x),
         'gastos por naturaleza = grupo 6';
  assert public.rv(r, '60') = 45000 and (select x ->> 'label' from jsonb_array_elements(r -> 'rows') x where x ->> 'key' = '60') = 'Compras',
         'el subgrupo 60 con su nombre del PGC';
  assert r ->> 'base' = 'sales' and (r -> 'sales' ->> 'value')::numeric = 120000, 'el % de los gastos, sobre las ventas';
  raise notice 'OK  · clientes = cifra de negocios, gastos por naturaleza = grupo 6 y el caso al céntimo';

  -- 2027 hasta el 30/06, con el año anterior a la misma fecha
  t := erp.dashboard_data(c, 'ventas', 2027, '2027-06-30');
  r := public.rk(t, 'customers');
  assert (r -> 'total' ->> 'prev')::numeric = public.fs(c, 2026, 'pyg', 'P1', '2026-06-30'), 'el total del año anterior a la misma fecha';
  raise notice 'OK  · con «hasta» y el año anterior';
end $$;

-- ---------- Cobros, rectificativas y asientos con dos clientes (en modo guiado: la 430 y la 477 son controladas) ----------
reset role;
update erp.companies set control_mode = 'guided' where id = (select e from public.ctx where k = 'c');
-- un segundo cliente para el asiento con dos
insert into erp.gl_accounts (company_id, account_no, name, name_en, account_type, template_account, account_category)
select company_id, '43000009', 'Cliente Nuevo SL', 'Cliente Nuevo SL', account_type, template_account, account_category
from erp.gl_accounts where company_id = (select e from public.ctx where k = 'c') and account_no = '43000001';
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare c uuid := (select e from public.ctx where k = 'c'); fy uuid; a uuid; r0 jsonb; r jsonb;
        acc_venta uuid; acc_igic uuid;
begin
  fy := (select id from erp.fiscal_years where company_id = c and year = 2027);
  acc_venta := (select id from erp.gl_accounts where company_id = c and account_no like '700%' and length(account_no) = 8 limit 1);
  acc_igic := (select id from erp.gl_accounts where company_id = c and account_no = '47710007');
  r0 := public.rk(erp.dashboard_data(c, 'ventas', 2027), 'customers');

  -- una venta a dos clientes en un asiento: se reparte en proporción (300 y 100)
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description) values (c, fy, '2027-01-15', 'Venta a dos clientes') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit) values
    (a, (select id from erp.gl_accounts where company_id = c and account_no = '43000001'), 321),
    (a, (select id from erp.gl_accounts where company_id = c and account_no = '43000009'), 107);
  insert into erp.journal_lines (entry_id, gl_account_id, credit) values (a, acc_venta, 400), (a, acc_igic, 28);
  perform erp.post_entry(a);
  r := public.rk(erp.dashboard_data(c, 'ventas', 2027), 'customers');
  assert public.rv(r, '43000001') = coalesce(public.rv(r0, '43000001'), 0) + 300, format('al primero, 300: %s', public.rv(r, '43000001'));
  assert public.rv(r, '43000009') = 100, 'al segundo, 100';

  -- un cobro no es una venta
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description) values (c, fy, '2027-01-20', 'Cobro') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit) values (a, (select id from erp.gl_accounts where company_id = c and account_no = '57200001'), 321);
  insert into erp.journal_lines (entry_id, gl_account_id, credit) values (a, (select id from erp.gl_accounts where company_id = c and account_no = '43000001'), 321);
  perform erp.post_entry(a);
  r0 := r;
  r := public.rk(erp.dashboard_data(c, 'ventas', 2027), 'customers');
  assert public.rv(r, '43000001') = public.rv(r0, '43000001'), format('el cobro no cuenta: %s', public.rv(r, '43000001'));

  -- una rectificativa (abono) resta
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description) values (c, fy, '2027-01-25', 'Rectificativa') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit) values (a, acc_venta, 50), (a, acc_igic, 3.5);
  insert into erp.journal_lines (entry_id, gl_account_id, credit) values (a, (select id from erp.gl_accounts where company_id = c and account_no = '43000009'), 53.5);
  perform erp.post_entry(a);
  r := public.rk(erp.dashboard_data(c, 'ventas', 2027), 'customers');
  assert public.rv(r, '43000009') = 50, 'la rectificativa resta: 100 − 50';
  assert public.rsum(r) = public.fs(c, 2027, 'pyg', 'P1', null), 'y el total sigue siendo la cifra de negocios';
  raise notice 'OK  · reparto entre dos clientes, el cobro no cuenta y la rectificativa resta';
end $$;

-- ---------- Los N primeros y el resto ----------
reset role;
update erp.dash_widgets set top_n = 1 where dashboard = 'ventas' and source = 'customers';
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare c uuid := (select e from public.ctx where k = 'c'); r jsonb;
begin
  r := public.rk(erp.dashboard_data(c, 'ventas', 2026), 'customers');
  assert jsonb_array_length(r -> 'rows') = 1 and (r -> 'rest' ->> 'count')::int = 1 and (r -> 'rest' ->> 'value')::numeric = 2000,
         'con 1: el primero y el resto (Cliente Dudoso, 2.000)';
  assert public.rsum(r) = 120000, 'el total no cambia';
  raise notice 'OK  · los N primeros y el «Resto»';
end $$;
reset role;
update erp.dash_widgets set top_n = 10 where dashboard = 'ventas' and source = 'customers';

-- ---------- Simulación: una venta en edición ----------
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare c uuid := (select e from public.ctx where k = 'c'); a uuid; antes jsonb; s jsonb;
begin
  antes := erp.dashboard_data(c, 'ventas', 2027);
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (c, (select id from erp.fiscal_years where company_id = c and year = 2027), '2027-02-10', 'Venta (borrador)') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit) values (a, (select id from erp.gl_accounts where company_id = c and account_no = '43000002'), 1070);
  insert into erp.journal_lines (entry_id, gl_account_id, credit) values
    (a, (select id from erp.gl_accounts where company_id = c and account_no like '700%' and length(account_no) = 8 limit 1), 1000),
    (a, (select id from erp.gl_accounts where company_id = c and account_no = '47710007'), 70);
  assert erp.dashboard_data(c, 'ventas', 2027) = antes, 'sin simulación, el borrador no cuenta';
  s := erp.dashboard_data(c, 'ventas', 2027, null, true);
  assert public.rv(public.rk(s, 'customers'), '43000002') = coalesce(public.rv(public.rk(antes, 'customers'), '43000002'), 0) + 1000,
         'con simulación, la venta suma al cliente';
  assert not erp.simulating();
  delete from erp.journal_lines where entry_id = a;
  delete from erp.journal_entries where id = a;
  raise notice 'OK  · la simulación con una venta en edición';
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare c uuid := (select e from public.ctx where k = 'c');
begin
  assert public.falla(format('select erp.dashboard_data(%L, %L, 2026)', c, 'ventas'), 'Not allowed'), 'otra empresa no ve nada';
  assert not exists (select 1 from erp.dash_ranking(c, 2026, null, 'customers')), 'ni sus clientes';
  assert not exists (select 1 from erp.dash_ranking(c, 2026, '2026-12-31', 'expense_groups')), 'ni sus gastos';
  raise notice 'OK  · otra empresa no ve el tablero';
end $$;
reset role;

-- ---------- El catálogo ----------
do $$
begin
  assert public.falla($q$insert into erp.dash_widgets (dashboard, sort, kind, label, label_en, metrics) values ('ventas', 99, 'ranking', 'x', 'x', '{}')$q$,
                      'dash_widgets_source_check'), 'un ranking necesita su fuente';
  assert public.falla($q$insert into erp.dash_widgets (dashboard, sort, kind, source, label, label_en, metrics) values ('ventas', 99, 'bars', 'customers', 'x', 'x', array['SALES'])$q$,
                      'dash_widgets_source_check'), 'solo el ranking tiene fuente';
  assert public.falla($q$insert into erp.dash_widgets (dashboard, sort, kind, source, label, label_en, metrics) values ('ventas', 99, 'ranking', 'partners', 'x', 'x', '{}')$q$,
                      'dash_widgets_source_check'), 'clientes, proveedores o gastos por naturaleza';
  assert (select count(*) from erp.dashboards) = 5, 'los cinco tableros';
  assert not exists (select 1 from erp.dash_widgets w, unnest(w.metrics) m(code)
                     where not exists (select 1 from erp.dash_metrics x where x.code = m.code)), 'cada tarjeta apunta a métricas que existen';
  assert not has_function_privilege('anon', 'erp.dash_ranking(uuid, integer, date, text)', 'execute');
  raise notice 'OK  · catálogo: la tarjeta de ranking y permisos';
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
  perform erp.dashboard_data(c, 'ventas', 2027, '2027-06-30');
  ms := extract(epoch from clock_timestamp() - t0) * 1000;
  assert ms < 3000, format('el tablero tarda %s ms', round(ms));
  raise notice 'OK  · el tablero en % ms con una empresa de 30.000 asientos al lado', round(ms);
end $$;
reset role;

\echo 'FASE 77 OK'
