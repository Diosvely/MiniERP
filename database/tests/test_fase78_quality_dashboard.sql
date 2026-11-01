-- =====================================================================
-- PRUEBAS FASE 78 · Tablero «Calidad de la contabilidad» y aviso de saldos al revés en el Balance (migración 0084 ·
-- v0.57.0)
-- ---------------------------------------------------------------------
-- Diseño validado por Diosvely (diseno-v0.57.0.md). Con el caso completo «Taller Atlántico SL» se comprueba lo que trae
-- (Reservas voluntarias deudora, cliente dudoso vencido a más de 90 días) y, en una empresa con 2026 abierto, se provoca
-- cada problema uno a uno:
--   · un proveedor deudor (aviso; su ⚠ en Existencias; regresión de la 400: no se compensa con los acreedores) y sin
--     conciliar con sus facturas; una caja acreedora (error); un borrador descuadrado;
--   · un trimestre sin liquidar (error) y los meses sin cerrar en la contabilidad mes a mes;
--   · la simulación, una empresa sin facturas («no aplica»), otra empresa no ve nada y rapidez con una empresa grande
--     al lado.
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
-- Una fila de la lista de control
create or replace function public.q(c uuid, y int, code text, d date default null, sim boolean default false) returns jsonb language sql as $$
  select to_jsonb(x) from erp.quality_checks(c, y, d, sim) x where x.code = $3;
$$;
grant execute on function public.q(uuid, int, text, date, boolean) to authenticated;
-- La tarjeta de ranking de una fuente
create or replace function public.rk(t jsonb, src text) returns jsonb language sql as $$
  select w -> 'ranking' from jsonb_array_elements(t -> 'widgets') w where w ->> 'source' = src;
$$;
grant execute on function public.rk(jsonb, text) to authenticated;
-- Un asiento contabilizado de dos líneas (debe, haber)
create or replace function public.asiento(c uuid, d date, txt text, cta_d text, cta_h text, imp numeric, contabilizar boolean default true)
returns uuid language plpgsql as $$
declare a uuid;
begin
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (c, (select id from erp.fiscal_years where company_id = c and year = extract(year from d)), d, txt) returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit) values (a, (select id from erp.gl_accounts where company_id = c and account_no = cta_d), imp);
  insert into erp.journal_lines (entry_id, gl_account_id, credit) values (a, (select id from erp.gl_accounts where company_id = c and account_no = cta_h), imp);
  if contabilizar then perform erp.post_entry(a); end if;
  return a;
end $$;
grant execute on function public.asiento(uuid, date, text, text, text, numeric, boolean) to authenticated;

-- ---------- El caso tal cual: lo que trae ----------
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare c uuid := (select e from public.ctx where k = 'c'); t jsonb;
begin
  assert (select count(*) from erp.quality_checks(c, 2026)) = 7, 'las 7 filas';
  -- un saldo al revés real: Reservas voluntarias deudora (gastos de la ampliación de capital contra reservas)
  assert public.q(c, 2026, 'anomalies') ->> 'value' = '1' and public.q(c, 2026, 'anomalies') ->> 'severity' = 'warning', 'Reservas voluntarias deudora';
  assert public.q(c, 2026, 'drafts') ->> 'severity' = 'ok', 'sin borradores';
  assert public.q(c, 2026, 'open_months') ->> 'severity' = 'na', 'no lleva la contabilidad mes a mes: no aplica';
  assert public.q(c, 2026, 'settlements') ->> 'severity' = 'ok', 'los cuatro trimestres liquidados';
  assert public.q(c, 2026, 'overdue_in') ->> 'severity' = 'error' and (public.q(c, 2026, 'overdue_in') ->> 'extra')::numeric = 2140,
         'el cliente dudoso: 2.140 vencidos a más de 90 días';
  assert public.q(c, 2026, 'unreconciled') ->> 'severity' = 'ok', 'los terceros cuadran con sus facturas';
  t := erp.dashboard_data(c, 'calidad', 2026);
  assert t ->> 'label' = 'Calidad de la contabilidad' and jsonb_array_length(t -> 'widgets') = 3;
  assert jsonb_array_length((select w -> 'checklist' from jsonb_array_elements(t -> 'widgets') w where w ->> 'kind' = 'checklist')) = 7,
         'la lista de control en el tablero';
  assert public.rk(t, 'anomalies') -> 'rows' -> 0 ->> 'key' = '11300001' and public.rk(t, 'anomalies') ->> 'base' = 'none', 'la cuenta al revés, en el ranking';
  assert public.rk(t, 'overdue_customers') -> 'rows' @> '[{"key": "43000002", "note": "Tiene facturas vencidas hace más de 90 días."}]'::jsonb,
         'el cliente dudoso, con su nota';
  assert exists (select 1 from erp.fs_line_anomalies(c, 2026) a where a.account_no = '11300001' and a.line_code like 'PN%'),
         'el aviso del Balance cae en el patrimonio neto';
  raise notice 'OK  · el caso: Reservas voluntarias al revés, cliente dudoso vencido a más de 90 días y el resto en verde';
end $$;
reset role;

-- ---------- Se provoca cada problema en una empresa con 2026 abierto ----------
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$ begin
  insert into public.ctx values ('abierta', (erp.create_case_company('taller_atlantico', 'until_closing')->>'company_id')::uuid);
end $$;
reset role;
update erp.companies set control_mode = 'guided' where id = (select e from public.ctx where k = 'abierta');
insert into erp.gl_accounts (company_id, account_no, name, name_en, account_type, template_account, account_category)
select company_id, '57000001', 'Caja', 'Cash', account_type, '570', account_category
from erp.gl_accounts where company_id = (select e from public.ctx where k = 'abierta') and account_no = '57200001';
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare c uuid := (select e from public.ctx where k = 'abierta'); ai numeric; prov numeric; a uuid; n0 int;
begin
  n0 := (public.q(c, 2026, 'anomalies') ->> 'value')::int;
  ai := (select x.amount from erp.financial_statement(c, 2026, 'balance', null) x where x.code = 'AC.I');
  prov := (select x.amount from erp.financial_statement(c, 2026, 'balance', null) x where x.code = 'PC.IV.1');
  -- 1) un proveedor con saldo deudor (pago de más a Maquinaria Atlántica): aviso, y además sin conciliar
  perform public.asiento(c, '2026-12-15', 'Pago duplicado', '40000002', '57200001', 5000);
  assert (public.q(c, 2026, 'anomalies') ->> 'value')::int = n0 + 1 and public.q(c, 2026, 'anomalies') ->> 'severity' = 'warning', 'proveedor deudor: aviso';
  assert exists (select 1 from erp.fs_line_anomalies(c, 2026) a where a.account_no = '40000002' and a.line_code like 'AC.I%'),
         'su ⚠ cae en Existencias (como un anticipo, 407)';
  -- regresión de la 400: no se compensa con los proveedores acreedores
  assert (select x.amount from erp.financial_statement(c, 2026, 'balance', null) x where x.code = 'AC.I') = ai + 5000, 'Existencias + 5.000';
  assert (select x.amount from erp.financial_statement(c, 2026, 'balance', null) x where x.code = 'PC.IV.1') = prov, 'Proveedores no cambia: no se compensa';
  assert (public.q(c, 2026, 'unreconciled') ->> 'value')::int >= 1, 'el proveedor no cuadra con sus facturas';
  -- 3) un borrador descuadrado
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (c, (select id from erp.fiscal_years where company_id = c and year = 2026), '2026-12-20', 'Descuadrado') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit) values (a, (select id from erp.gl_accounts where company_id = c and account_no = '57200001'), 10);
  insert into erp.journal_lines (entry_id, gl_account_id, credit) values (a, (select id from erp.gl_accounts where company_id = c and account_no = '57000001'), 7);
  assert public.q(c, 2026, 'drafts') @> '{"value": 1, "extra": 1, "severity": "warning"}'::jsonb, 'un borrador con problema';
  delete from erp.journal_lines where entry_id = a;
  delete from erp.journal_entries where id = a;
  raise notice 'OK  · proveedor deudor (Existencias, sin compensar), borrador descuadrado';
end $$;

-- 2) una caja acreedora: el ERP no deja contabilizarla (está bloqueada para saldos al revés), pero puede llegar en un
--    diario importado; se mete como una importación, sin disparadores
reset role;
set session_replication_role = replica;
with c as (select e as cid from public.ctx where k = 'abierta'),
     ins as (insert into erp.journal_entries (company_id, fiscal_year_id, entry_no, posting_date, description, status)
             select (select cid from c), (select id from erp.fiscal_years where company_id = (select cid from c) and year = 2026),
                    90001, '2026-12-16', 'Importado: gasto pagado sin dinero en caja', 'posted' returning id)
insert into erp.journal_lines (company_id, entry_id, gl_account_id, debit, credit, line_no)
select (select cid from c), i.id, a.id, case when a.account_no = '62300001' then 100 else 0 end,
       case when a.account_no = '57000001' then 100 else 0 end, case when a.account_no = '62300001' then 1 else 2 end
from ins i cross join erp.gl_accounts a where a.company_id = (select cid from c) and a.account_no in ('62300001', '57000001');
set session_replication_role = origin;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare c uuid := (select e from public.ctx where k = 'abierta');
begin
  -- 2) una caja acreedora: imposible → error
  assert public.q(c, 2026, 'anomalies') ->> 'severity' = 'error' and (public.q(c, 2026, 'anomalies') ->> 'extra')::int = 1, 'caja acreedora: error';
  assert exists (select 1 from erp.fs_line_anomalies(c, 2026) a where a.account_no = '57000001' and a.severity = 'error' and a.line_code like 'PC%'),
         'su ⚠ cae en el pasivo corriente';
  raise notice 'OK  · caja acreedora importada: error, con su ⚠ en el pasivo corriente';
end $$;

-- 4) un trimestre sin liquidar (se anula la del 3T) y 5) la contabilidad mes a mes
reset role;
do $$
declare c uuid := (select e from public.ctx where k = 'abierta');
begin
  -- solo se puede anular la última: primero la del 4T y después la del 3T
  perform erp.cancel_tax_settlement((select id from erp.tax_settlements where company_id = c and year = 2026 and quarter = 4 and status = 'posted'));
  perform erp.cancel_tax_settlement((select id from erp.tax_settlements where company_id = c and year = 2026 and quarter = 3 and status = 'posted'));
end $$;
update erp.companies set monthly = true where id = (select e from public.ctx where k = 'abierta');
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare c uuid := (select e from public.ctx where k = 'abierta');
begin
  -- el 3T ya terminó; el 4T cuenta solo si hoy ya pasó el 31/12/2026
  assert (public.q(c, 2026, 'settlements') ->> 'value')::int = 1 + (current_date > '2026-12-31')::int
     and public.q(c, 2026, 'settlements') ->> 'severity' = 'error', format('el 3T sin liquidar: %s', public.q(c, 2026, 'settlements'));
  assert public.q(c, 2026, 'settlements', '2026-06-30') ->> 'value' = '0', 'a 30/06, el 3T todavía no había terminado';
  assert (public.q(c, 2026, 'open_months') ->> 'value')::int > 0 and public.q(c, 2026, 'open_months') ->> 'severity' = 'warning',
         'mes a mes: los meses terminados sin cerrar';
  raise notice 'OK  · liquidación pendiente (error) y meses sin cerrar en la contabilidad mes a mes';
end $$;

-- ---------- Simulación: una caja acreedora en edición ----------
do $$
declare c uuid := (select e from public.ctx where k = 'c'); a uuid; n int;
begin
  -- (en el caso, 2026 está cerrado: se usa 2027)
  n := (public.q(c, 2027, 'anomalies') ->> 'value')::int;
  a := public.asiento(c, '2027-02-10', 'Caja acreedora (borrador)', '62300001', '57200001', 999999, false);
  assert (public.q(c, 2027, 'anomalies') ->> 'value')::int = n, 'sin simulación, el borrador no cuenta';
  assert (public.q(c, 2027, 'anomalies', null, true) ->> 'value')::int = n + 1, 'con simulación, el banco queda acreedor';
  assert exists (select 1 from erp.fs_line_anomalies(c, 2027, null, true) x where x.account_no = '57200001'), 'y el Balance lo avisa';
  assert not erp.simulating(), 'al terminar, la simulación se apaga';
  delete from erp.journal_lines where entry_id = a;
  delete from erp.journal_entries where id = a;
  raise notice 'OK  · la simulación con un asiento en edición';
end $$;

-- ---------- Una empresa sin facturas (como una importada): vencidos y conciliación no aplican ----------
do $$
declare c uuid; y int;
begin
  insert into erp.companies (name, industry, tax_territory, created_by) values ('Importada', 'services', 'mainland', auth.uid()) returning id into c;
  perform erp.create_fiscal_year(c, 2026);
  y := 2026;
  assert public.q(c, y, 'overdue_in') ->> 'severity' = 'na' and public.q(c, y, 'unreconciled') ->> 'severity' = 'na', 'sin facturas, no aplica';
  assert public.q(c, y, 'settlements') ->> 'severity' in ('na', 'ok'), 'sin liquidaciones configuradas o al día';
  raise notice 'OK  · sin facturas en el ERP: «no aplica»';
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare c uuid := (select e from public.ctx where k = 'c');
begin
  assert public.falla(format('select * from erp.quality_checks(%L, 2026)', c), 'Not allowed'), 'otra empresa no ve la lista';
  assert public.falla(format('select * from erp.fs_line_anomalies(%L, 2026)', c), 'Not allowed'), 'ni el aviso del Balance';
  assert not exists (select 1 from erp.dash_ranking(c, 2026, null, 'anomalies')), 'ni sus cuentas';
  raise notice 'OK  · otra empresa no ve nada';
end $$;
reset role;

-- ---------- El catálogo ----------
do $$
begin
  assert (select count(*) from erp.quality_check_defs) = 7, 'los textos de las 7 filas';
  assert (select count(*) from erp.dashboards) = 6, 'el Resumen de dirección y los cinco tableros nuevos';
  assert public.falla($q$insert into erp.dash_widgets (dashboard, sort, kind, source, label, label_en, metrics) values ('calidad', 99, 'checklist', 'anomalies', 'x', 'x', '{}')$q$,
                      'dash_widgets_source_check'), 'la lista de control no tiene fuente';
  assert not has_function_privilege('anon', 'erp.quality_checks(uuid, integer, date, boolean)', 'execute');
  assert not has_function_privilege('anon', 'erp.fs_line_anomalies(uuid, integer, date, boolean)', 'execute');
  assert has_function_privilege('authenticated', 'erp.fs_line_anomalies(uuid, integer, date, boolean)', 'execute');
  raise notice 'OK  · catálogo y permisos';
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
  perform erp.dashboard_data(c, 'calidad', 2027, '2027-06-30');
  ms := extract(epoch from clock_timestamp() - t0) * 1000;
  assert ms < 3000, format('el tablero tarda %s ms', round(ms));
  raise notice 'OK  · el tablero en % ms con una empresa de 30.000 asientos al lado', round(ms);
end $$;
reset role;

\echo 'FASE 78 OK'
