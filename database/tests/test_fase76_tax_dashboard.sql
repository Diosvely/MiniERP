-- =====================================================================
-- PRUEBAS FASE 76 · Tablero «Impuestos» (migración 0082 · v0.55.0)
-- ---------------------------------------------------------------------
-- Diseño validado por Diosvely (diseno-v0.55.0.md). Con el caso completo «Taller Atlántico SL», que es canario (IGIC),
-- se comprueba que:
--   · devengado, deducible y resultado de cada trimestre = la liquidación del ERP de ese trimestre (y la contabilizada);
--     regresión: si contaran los asientos de liquidación, el devengado de cada trimestre bajaría a cero;
--   · las retenciones practicadas de cada trimestre = las de los modelos (withholding_summary);
--   · «hasta» a mitad de trimestre, el año anterior por trimestres y la simulación con una venta en edición;
--   · la liquidación lee la misma lista de cuentas (erp.tax_accounts); otra empresa no ve nada; rapidez con una
--     empresa grande al lado.
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

-- ---------- Cada trimestre = su liquidación ----------
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare c uuid := (select e from public.ctx where k = 'c'); t jsonb; q int; l jsonb; w numeric;
begin
  t := erp.dashboard_data(c, 'impuestos', 2026);
  assert t ->> 'label' = 'Impuestos' and t ->> 'tax_type' = 'IGIC', 'el caso es canario: IGIC';
  assert (select count(*) from jsonb_array_elements(t -> 'widgets')) = 5, 'las 5 tarjetas';
  assert jsonb_array_length(public.item(t, 'TAX_OUT') -> 'series') = 4, 'cuatro trimestres';
  for q in 1..4 loop
    l := erp.tax_settlement_calc(c, 'IGIC', 2026, q);
    assert (public.item(t, 'TAX_OUT') -> 'series' ->> (q - 1))::numeric = (l ->> 'output_tax')::numeric,
           format('devengado del %sT: %s frente a %s', q, public.item(t, 'TAX_OUT') -> 'series' ->> (q - 1), l ->> 'output_tax');
    assert (public.item(t, 'TAX_IN') -> 'series' ->> (q - 1))::numeric = (l ->> 'input_tax')::numeric, format('deducible del %sT', q);
    assert (public.item(t, 'TAX_RES') -> 'series' ->> (q - 1))::numeric = (l ->> 'result')::numeric, format('resultado del %sT', q);
    -- y la liquidación contabilizada de ese trimestre (sin compensaciones en el caso)
    assert (public.item(t, 'TAX_RES') -> 'series' ->> (q - 1))::numeric
         = (select s.final_result from erp.tax_settlements s where s.company_id = c and s.year = 2026 and s.quarter = q and s.status = 'posted'),
           format('resultado contabilizado del %sT', q);
    -- retenciones practicadas = las de los modelos del trimestre
    select coalesce(sum(x.amount), 0) into w from erp.withholding_summary(c, 2026, q) x where x.side = 'withheld';
    assert (public.item(t, 'WHT_OUT') -> 'series' ->> (q - 1))::numeric = w, format('retenciones del %sT: %s', q, w);
  end loop;
  -- Caso: 1T 1.750 − 812 = 938; 2T 308; 3T 658; 4T 308
  assert public.item(t, 'TAX_RES') -> 'series' = '[938.00, 308.00, 658.00, 308.00]'::jsonb, 'los resultados del caso';
  assert (public.item(t, 'TAX_OUT') ->> 'value')::numeric = 8400 and (public.item(t, 'TAX_RES') ->> 'value')::numeric = 2212,
         'en el año: 8.400 devengados y 2.212 de resultado';
  assert (public.item(t, 'TAX_RATE') ->> 'value')::numeric = round(8400 / public.fs(c, 2026, 'pyg', 'P1', null), 4), 'tipo medio = 7 %';
  raise notice 'OK  · cada trimestre = su liquidación (devengado, deducible, resultado y retenciones)';

  -- «Hasta» a mitad de trimestre: el trimestre en curso llega hasta la fecha; los siguientes, sin dato
  t := erp.dashboard_data(c, 'impuestos', 2026, '2026-05-15');
  assert (public.item(t, 'TAX_OUT') -> 'series' ->> 0)::numeric = 1750, '1T entero';
  assert (public.item(t, 'TAX_OUT') -> 'series' ->> 1)::numeric = (public.item(t, 'TAX_OUT') ->> 'value')::numeric - 1750,
         '2T hasta el 15/05';
  assert public.item(t, 'TAX_OUT') -> 'series' -> 2 = 'null'::jsonb and public.item(t, 'TAX_OUT') -> 'series' -> 3 = 'null'::jsonb,
         'después de «hasta», sin dato';

  -- 2027 frente a 2026 a la misma fecha, y los trimestres de 2026 enteros
  t := erp.dashboard_data(c, 'impuestos', 2027, '2027-06-30');
  assert (t ->> 'has_prev')::boolean;
  assert public.item(t, 'TAX_RES') -> 'series_prev' = '[938.00, 308.00, 658.00, 308.00]'::jsonb, 'los trimestres del año anterior';
  assert (public.item(t, 'TAX_OUT') ->> 'prev')::numeric = 1750 + 3850, 'devengado del año anterior hasta el 30/06';
  raise notice 'OK  · «hasta» a mitad de trimestre y el año anterior';
end $$;

-- ---------- Una venta en edición, en la simulación ----------
-- (en modo estricto, un asiento manual sobre la 477 no se puede contabilizar ni simular: se pasa la empresa a guiado)
reset role;
update erp.companies set control_mode = 'guided' where id = (select e from public.ctx where k = 'c');
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare c uuid := (select e from public.ctx where k = 'c'); a uuid; antes jsonb; s jsonb;
begin
  antes := erp.dashboard_data(c, 'impuestos', 2027, '2027-06-30');
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (c, (select id from erp.fiscal_years where company_id = c and year = 2027), '2027-02-10', 'Venta (borrador)') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit) values (a, (select id from erp.gl_accounts where company_id = c and account_no = '57200001'), 1070);
  insert into erp.journal_lines (entry_id, gl_account_id, credit)
  values (a, (select id from erp.gl_accounts where company_id = c and account_no like '70%' and length(account_no) = 8 limit 1), 1000);
  insert into erp.journal_lines (entry_id, gl_account_id, credit) values (a, (select id from erp.gl_accounts where company_id = c and account_no = '47710007'), 70);
  assert erp.dashboard_data(c, 'impuestos', 2027, '2027-06-30') = antes, 'sin simulación, el borrador no cuenta';
  s := erp.dashboard_data(c, 'impuestos', 2027, '2027-06-30', true);
  assert (public.item(s, 'TAX_OUT') -> 'series' ->> 0)::numeric = coalesce((public.item(antes, 'TAX_OUT') -> 'series' ->> 0)::numeric, 0) + 70,
         'el IGIC de la venta cae en el 1T';
  assert not erp.simulating(), 'al terminar, la simulación se apaga';
  delete from erp.journal_lines where entry_id = a;
  delete from erp.journal_entries where id = a;
  raise notice 'OK  · la simulación con una venta en edición';
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare c uuid := (select e from public.ctx where k = 'c');
begin
  assert public.falla(format('select erp.dashboard_data(%L, %L, 2026)', c, 'impuestos'), 'Not allowed'), 'otra empresa no ve nada';
  assert not exists (select 1 from erp.tax_moves_at(c, 2026, array['2026-12-31'::date]) x where x.output_tax <> 0 or x.input_tax <> 0),
         'ni su IGIC';
  assert not exists (select 1 from erp.account_moves_at(c, 2026, array['2026-12-31'::date], array['4751']) x where x.credit <> 0),
         'ni sus retenciones';
  raise notice 'OK  · otra empresa no ve el tablero';
end $$;
reset role;

-- ---------- La liquidación usa la misma lista de cuentas (y sigue calculando lo mismo) ----------
do $$
declare c uuid := (select e from public.ctx where k = 'c');
begin
  assert position('erp.tax_accounts' in pg_get_functiondef('erp.tax_settlement_calc(uuid, text, integer, integer, boolean)'::regprocedure)) > 0,
         'la liquidación lee erp.tax_accounts';
  assert (select count(*) from erp.tax_accounts(c, 'IGIC') a join erp.gl_accounts g on g.id = a.id
          where (g.account_no = '47710007' and a.side = 'output') or (g.account_no = '47210007' and a.side = 'input')) = 2,
         'las cuentas de IGIC del caso, cada una en su lado';
  assert public.falla($q$insert into erp.dash_widgets (dashboard, sort, kind, mode, label, label_en, metrics)
                        values ('impuestos', 99, 'lines', 'quarter', 'x', 'x', array['TAX_OUT'])$q$, 'dash_widgets_quarter_kind'),
         'los trimestres, solo en barras';
  assert public.falla($q$insert into erp.dash_metrics (code, sort, label, label_en, unit, kind, flow) values ('X', 999, 'x', 'x', 'eur', 'move', 'credit')$q$,
                      'dash_metrics_check'), 'un movimiento de cuenta necesita su cuenta';
  assert public.falla($q$insert into erp.dash_metrics (code, sort, label, label_en, unit, kind, flow) values ('X', 999, 'x', 'x', 'eur', 'tax', 'in')$q$,
                      'dash_metrics_check'), 'el impuesto es devengado o deducible';
  -- regresión: «flow in (…)» con el sentido vacío daba NULL y la restricción lo aceptaba
  assert public.falla($q$insert into erp.dash_metrics (code, sort, label, label_en, unit, kind) values ('X', 999, 'x', 'x', 'eur', 'tax')$q$,
                      'dash_metrics_check'), 'un impuesto sin sentido no vale';
  assert public.falla($q$insert into erp.dash_metrics (code, sort, label, label_en, unit, kind, account_prefix) values ('X', 999, 'x', 'x', 'eur', 'move', '4751')$q$,
                      'dash_metrics_check'), 'un movimiento de cuenta sin sentido no vale';
  assert not exists (select 1 from erp.dash_widgets w, unnest(w.metrics) m(code)
                     where not exists (select 1 from erp.dash_metrics x where x.code = m.code)), 'cada tarjeta apunta a métricas que existen';
  assert not exists (select 1 from erp.dash_metrics m join erp.dash_metrics a on a.code in (m.a, m.b) where a.sort >= m.sort),
         'una métrica solo usa métricas que se calculan antes';
  assert not has_function_privilege('anon', 'erp.tax_moves_at(uuid, integer, date[])', 'execute');
  assert not has_function_privilege('anon', 'erp.account_moves_at(uuid, integer, date[], text[])', 'execute');
  raise notice 'OK  · la liquidación y el tablero comparten la lista de cuentas; catálogo y permisos';
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
  perform erp.dashboard_data(c, 'impuestos', 2027, '2027-06-30');
  ms := extract(epoch from clock_timestamp() - t0) * 1000;
  assert ms < 3000, format('el tablero tarda %s ms', round(ms));
  raise notice 'OK  · el tablero en % ms con una empresa de 30.000 asientos al lado', round(ms);
end $$;
reset role;

\echo 'FASE 76 OK'
