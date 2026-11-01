-- =====================================================================
-- PRUEBAS FASE 75 · Tablero «Tesorería y circulante» (migración 0081 · v0.54.0)
-- ---------------------------------------------------------------------
-- Diseño validado por Diosvely (diseno-v0.54.0.md). Con el caso completo «Taller Atlántico SL» (2026 cerrado y 2027
-- abierto) se comprueba que:
--   · tesorería, clientes, proveedores y fondo de maniobra cuadran con el Balance a cada fin de mes;
--   · entradas − salidas de tesorería acumuladas = tesorería a la fecha − tesorería de apertura, en los 12 fines de mes;
--   · un traspaso entre cuentas de tesorería (572 → 570) no es ni entrada ni salida; un pago, sí (regresión: sumar
--     apunte a apunte en lugar de asiento a asiento contaría el traspaso dos veces);
--   · liquidez general, prueba ácida, disponibilidad y periodos medios al cierre = pantalla Ratios, y a mitad de año
--     los periodos medios usan los días transcurridos;
--   · «hasta» con el año anterior, simulación, otra empresa no ve nada y rapidez con una empresa grande al lado.
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
-- La suma de una serie hasta el mes i (incluido)
create or replace function public.acum(s jsonb, i int) returns numeric language sql as $$
  select coalesce(sum(x::numeric), 0) from jsonb_array_elements_text(s) with ordinality e(x, n) where n <= i + 1;
$$;
grant execute on function public.acum(jsonb, int) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
begin
  insert into public.ctx values ('c', (erp.create_case_company('taller_atlantico', 'full')->>'company_id')::uuid);
end $$;
reset role;
-- una caja para el traspaso (570), como la subcuenta del banco
insert into erp.gl_accounts (company_id, account_no, name, name_en, account_type, template_account, account_category)
select company_id, '57000001', 'Caja', 'Cash', account_type, '570', account_category
from erp.gl_accounts where company_id = (select e from public.ctx where k = 'c') and account_no = '57200001';

-- ---------- El tablero cuadra con el Balance, el EFE y Ratios ----------
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare c uuid := (select e from public.ctx where k = 'c'); t jsonb; m date; i int; apertura numeric;
begin
  t := erp.dashboard_data(c, 'tesoreria', 2026);
  assert t ->> 'label' = 'Tesorería y circulante';
  assert (select count(*) from jsonb_array_elements(t -> 'widgets')) = 5, 'las 5 tarjetas';
  -- Cifras clave al cierre
  assert (public.item(t, 'CASH') ->> 'value')::numeric = public.fs(c, 2026, 'balance', 'AC.VI', null), 'tesorería = efectivo';
  assert (public.item(t, 'CUST') ->> 'value')::numeric = public.fs(c, 2026, 'balance', 'AC.II.1', null), 'clientes = Balance';
  assert (public.item(t, 'SUPP') ->> 'value')::numeric = public.fs(c, 2026, 'balance', 'PC.IV.1', null), 'proveedores = Balance';
  assert (public.item(t, 'CUST') ->> 'value')::numeric = 21400 and (public.item(t, 'SUPP') ->> 'value')::numeric = 16050,
         'caso: clientes 21.400 y proveedores 16.050';
  -- Igual que la pantalla Ratios al cierre (la disponibilidad es el ratio CASH de Ratios)
  assert (public.item(t, 'CR') ->> 'value')::numeric = (select r.value from erp.financial_ratios(c, 2026) r where r.code = 'CR'), 'CR = Ratios';
  assert (public.item(t, 'QR') ->> 'value')::numeric = (select r.value from erp.financial_ratios(c, 2026) r where r.code = 'QR'), 'QR = Ratios';
  assert (public.item(t, 'CASHR') ->> 'value')::numeric = (select r.value from erp.financial_ratios(c, 2026) r where r.code = 'CASH'), 'disponibilidad = Ratios';
  assert (public.item(t, 'DSO') ->> 'value')::numeric = (select r.value from erp.financial_ratios(c, 2026) r where r.code = 'DSO'), 'cobro = Ratios';
  assert (public.item(t, 'DPO') ->> 'value')::numeric = (select r.value from erp.financial_ratios(c, 2026) r where r.code = 'DPO'), 'pago = Ratios';
  assert (public.item(t, 'DSO') ->> 'ref_max')::numeric = 60 and public.item(t, 'DSO') ->> 'unit' = 'days', 'zona y unidad de Ratios';
  raise notice 'OK  · cifras clave y liquidez = Balance y Ratios';

  -- Entradas − salidas acumuladas = tesorería − tesorería de apertura, en los 12 fines de mes
  apertura := public.fs(c, 2026, 'balance', 'AC.VI', '2026-01-01') - coalesce((
    select sum(l.debit - l.credit) from erp.journal_entries e join erp.journal_lines l on l.entry_id = e.id
    join erp.gl_accounts g on g.id = l.gl_account_id
    where e.company_id = c and e.posting_date = '2026-01-01' and e.entry_type = 'normal' and e.status = 'posted'
      and g.account_no like '57%'), 0);
  for i in 0..11 loop
    m := (t -> 'months' ->> i)::date;
    assert (public.item(t, 'CASH') -> 'series' ->> i)::numeric = public.fs(c, 2026, 'balance', 'AC.VI', m), format('tesorería a %s', m);
    assert (public.item(t, 'WC') -> 'series' ->> i)::numeric
         = public.fs(c, 2026, 'balance', 'AC', m) - public.fs(c, 2026, 'balance', 'PC', m), format('fondo de maniobra a %s', m);
    assert public.acum(public.item(t, 'CASH_IN') -> 'series', i) - public.acum(public.item(t, 'CASH_OUT') -> 'series', i)
         = public.fs(c, 2026, 'balance', 'AC.VI', m) - apertura, format('entradas − salidas = variación de tesorería a %s', m);
    assert (public.item(t, 'CASH_IN') -> 'series' ->> i)::numeric >= 0 and (public.item(t, 'CASH_OUT') -> 'series' ->> i)::numeric >= 0,
           'entradas y salidas en positivo';
  end loop;
  assert (public.item(t, 'CASH_IN') ->> 'value')::numeric = 210860 and (public.item(t, 'CASH_OUT') ->> 'value')::numeric = 81000,
         'caso: entraron 210.860 y salieron 81.000';
  raise notice 'OK  · entradas − salidas = variación de la tesorería en los 12 fines de mes';

  -- A mitad de año, los periodos medios con los días transcurridos (181 hasta el 30/06), no × 365
  t := erp.dashboard_data(c, 'tesoreria', 2026, '2026-06-30');
  assert (public.item(t, 'DSO') ->> 'value')::numeric is not distinct from
         case when public.fs(c, 2026, 'pyg', 'P1', '2026-06-30') = 0 then null
              else round(public.fs(c, 2026, 'balance', 'AC.II.1', '2026-06-30') * 181 / public.fs(c, 2026, 'pyg', 'P1', '2026-06-30'), 4) end,
         format('periodo de cobro a 30/06 con 181 días: %s', public.item(t, 'DSO') ->> 'value');
  raise notice 'OK  · periodos medios con los días transcurridos del ejercicio';

  -- 2027 hasta el 30/06, frente a 2026 a la misma fecha
  t := erp.dashboard_data(c, 'tesoreria', 2027, '2027-06-30');
  assert (t ->> 'has_prev')::boolean and t ->> 'prev_to' = '2026-06-30';
  assert (public.item(t, 'CASH_IN') ->> 'prev')::numeric = public.acum((erp.dashboard_data(c, 'tesoreria', 2026) -> 'widgets' -> 1 -> 'items' -> 0 -> 'series'), 5),
         'entradas del año anterior hasta el 30/06';
  assert (public.item(t, 'CASH') ->> 'prev')::numeric = public.fs(c, 2026, 'balance', 'AC.VI', '2026-06-30');
  raise notice 'OK  · con «hasta» y el año anterior a la misma fecha';
end $$;

-- ---------- Un traspaso entre cuentas de tesorería no es ni entrada ni salida; un pago, sí ----------
do $$
declare c uuid := (select e from public.ctx where k = 'c'); fy uuid; a uuid; antes jsonb; despues jsonb;
begin
  fy := (select id from erp.fiscal_years where company_id = c and year = 2027);
  antes := erp.dashboard_data(c, 'tesoreria', 2027, '2027-06-30');
  -- traspaso del banco a la caja (572 → 570)
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description) values (c, fy, '2027-01-20', 'Traspaso a caja') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit) values (a, (select id from erp.gl_accounts where company_id = c and account_no = '57000001'), 500);
  insert into erp.journal_lines (entry_id, gl_account_id, credit) values (a, (select id from erp.gl_accounts where company_id = c and account_no = '57200001'), 500);
  perform erp.post_entry(a);
  despues := erp.dashboard_data(c, 'tesoreria', 2027, '2027-06-30');
  assert (public.item(despues, 'CASH_IN') ->> 'value')::numeric = (public.item(antes, 'CASH_IN') ->> 'value')::numeric,
         format('el traspaso no es una entrada: %s', public.item(despues, 'CASH_IN') ->> 'value');
  assert (public.item(despues, 'CASH_OUT') ->> 'value')::numeric = (public.item(antes, 'CASH_OUT') ->> 'value')::numeric, 'ni una salida';
  assert (public.item(despues, 'CASH') ->> 'value')::numeric = (public.item(antes, 'CASH') ->> 'value')::numeric, 'la tesorería no cambia';
  -- un pago desde la caja: salida de 120 en enero
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description) values (c, fy, '2027-01-25', 'Material de oficina') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit) values (a, (select id from erp.gl_accounts where company_id = c and account_no like '62%' and length(account_no) = 8 limit 1), 120);
  insert into erp.journal_lines (entry_id, gl_account_id, credit) values (a, (select id from erp.gl_accounts where company_id = c and account_no = '57000001'), 120);
  perform erp.post_entry(a);
  despues := erp.dashboard_data(c, 'tesoreria', 2027, '2027-06-30');
  assert (public.item(despues, 'CASH_OUT') ->> 'value')::numeric = (public.item(antes, 'CASH_OUT') ->> 'value')::numeric + 120, 'el pago es una salida';
  assert (public.item(despues, 'CASH_OUT') -> 'series' ->> 0)::numeric = (public.item(antes, 'CASH_OUT') -> 'series' ->> 0)::numeric + 120, 'en enero';
  raise notice 'OK  · un traspaso entre cuentas 57 no cuenta; un pago, sí';
end $$;

-- ---------- Simulación: un cobro en edición ----------
do $$
declare c uuid := (select e from public.ctx where k = 'c'); a uuid; antes jsonb; s jsonb;
begin
  antes := erp.dashboard_data(c, 'tesoreria', 2027, '2027-06-30');
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (c, (select id from erp.fiscal_years where company_id = c and year = 2027), '2027-03-15', 'Aportación (borrador)') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit) values (a, (select id from erp.gl_accounts where company_id = c and account_no = '57200001'), 2000);
  insert into erp.journal_lines (entry_id, gl_account_id, credit)
  values (a, (select id from erp.gl_accounts where company_id = c and account_no like '1%' and length(account_no) = 8 limit 1), 2000);
  assert erp.dashboard_data(c, 'tesoreria', 2027, '2027-06-30') = antes, 'sin simulación, el borrador no cuenta';
  s := erp.dashboard_data(c, 'tesoreria', 2027, '2027-06-30', true);
  assert (public.item(s, 'CASH_IN') -> 'series' ->> 2)::numeric = (public.item(antes, 'CASH_IN') -> 'series' ->> 2)::numeric + 2000, 'entra en marzo';
  assert (public.item(s, 'CASH') ->> 'value')::numeric = (public.item(antes, 'CASH') ->> 'value')::numeric + 2000, 'y sube la tesorería';
  assert not erp.simulating(), 'al terminar, la simulación se apaga';
  delete from erp.journal_lines where entry_id = a;
  delete from erp.journal_entries where id = a;
  raise notice 'OK  · la simulación con un borrador';
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare c uuid := (select e from public.ctx where k = 'c');
begin
  assert public.falla(format('select erp.dashboard_data(%L, %L, 2027)', c, 'tesoreria'), 'Not allowed'), 'otra empresa no ve nada';
  assert not exists (select 1 from erp.cash_moves_at(c, 2026, array['2026-12-31'::date]) x where x.cash_in <> 0 or x.cash_out <> 0),
         'ni sus entradas y salidas';
  raise notice 'OK  · otra empresa no ve el tablero';
end $$;
reset role;

-- ---------- El catálogo ----------
do $$
begin
  assert public.falla($q$insert into erp.dash_metrics (code, sort, label, label_en, unit, kind) values ('X', 999, 'x', 'x', 'eur', 'cash')$q$,
                      'dash_metrics_check'), 'un movimiento de tesorería necesita su sentido';
  assert public.falla($q$insert into erp.dash_metrics (code, sort, label, label_en, unit, kind, flow) values ('X', 999, 'x', 'x', 'eur', 'cash', 'both')$q$,
                      'dash_metrics_'), 'entradas o salidas, nada más';   -- 0082: lo rechazan dash_metrics_check y dash_metrics_flow_check
  assert (select count(*) from erp.dashboards where code in ('resumen', 'rentabilidad', 'tesoreria')) = 3, 'los tres tableros';
  assert not exists (select 1 from erp.dash_widgets w, unnest(w.metrics) m(code)
                     where not exists (select 1 from erp.dash_metrics x where x.code = m.code)), 'cada tarjeta apunta a métricas que existen';
  assert not exists (select 1 from erp.dash_metrics m join erp.dash_metrics a on a.code in (m.a, m.b) where a.sort >= m.sort),
         'una métrica solo usa métricas que se calculan antes';
  assert not exists (select 1 from erp.dash_metrics m where m.kind = 'line'
                     and not exists (select 1 from erp.fs_lines l where l.statement = m.statement and l.code = m.line_code)),
         'cada partida existe en el Balance o la PyG';
  assert not has_function_privilege('anon', 'erp.cash_moves_at(uuid, integer, date[])', 'execute');
  assert (select coalesce('jit=off' = any (p.proconfig), false) from pg_proc p
          where p.oid = 'erp.dash_metric_values(uuid, integer, date[])'::regprocedure), 'sin JIT, como en la 0076';
  raise notice 'OK  · catálogo: tipos «cash» y «days» y permisos';
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
  perform erp.dashboard_data(c, 'tesoreria', 2027, '2027-06-30');
  ms := extract(epoch from clock_timestamp() - t0) * 1000;
  assert ms < 3000, format('el tablero tarda %s ms', round(ms));
  raise notice 'OK  · el tablero en % ms con una empresa de 30.000 asientos al lado', round(ms);
end $$;
reset role;

\echo 'FASE 75 OK'
