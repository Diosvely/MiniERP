-- =====================================================================
-- PRUEBAS FASE 72 · Cada empresa, independiente del tamaño de las demás (migración 0078 · v0.52.3)
-- ---------------------------------------------------------------------
-- Regresión: en Supabase, Comprobaciones de una empresa importada grande tardaba 12–20 s porque varias consultas recorrían los
-- apuntes y asientos de TODA la base (las demás empresas grandes incluidas). Se comprueba que el tiempo de
-- Comprobaciones, el balance, los flujos, el tablero y el Inicio de una empresa pequeña casi no cambia al añadir
-- otra empresa, de otro usuario, con 150.000 asientos.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'owner@test.local'),
                                          ('00000000-0000-0000-0000-0000000000b2', 'otro@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);
create table public.ctx (k text primary key, e uuid);
create table public.tiempos (k text primary key, ms numeric);
grant all on public.ctx, public.tiempos to authenticated;

-- Lo que hace la web al abrir las pantallas de informes de una empresa, en milisegundos
create or replace function public.medir(c uuid) returns numeric language plpgsql as $$
declare t0 timestamptz := clock_timestamp();
begin
  perform count(*) from erp.run_audit_checks(c, 2026, '2026-12-31');
  perform count(*) from erp.financial_statement(c, 2026, 'balance');
  perform count(*) from erp.cash_flow_statement(c, 2026, 'indirect');
  perform erp.dashboard_data(c, 'resumen', 2026);
  perform erp.home_kpis(c, '2026-12-31');
  return extract(epoch from clock_timestamp() - t0) * 1000;
end $$;
grant execute on function public.medir(uuid) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$ begin
  insert into public.ctx values ('caso', (erp.create_case_company('taller_atlantico', 'until_closing')->>'company_id')::uuid);
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$ begin
  insert into public.ctx values ('grande', (erp.create_case_company('taller_atlantico', 'until_closing')->>'company_id')::uuid);
end $$;
reset role;
analyze;

-- Tiempo con la base pequeña (la mejor de tres, para no medir la caché)
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare c uuid := (select e from public.ctx where k = 'caso');
begin
  insert into public.tiempos values ('antes', least(public.medir(c), public.medir(c), public.medir(c)));
end $$;
reset role;

-- La otra empresa crece: 150.000 asientos y 300.000 apuntes (sin disparadores: es solo volumen)
set session_replication_role = replica;
with c as (select e as cid from public.ctx where k = 'grande'),
     fy as (select id from erp.fiscal_years where company_id = (select cid from c) and year = 2026),
     ins as (insert into erp.journal_entries (company_id, fiscal_year_id, entry_no, posting_date, description, status)
             select (select cid from c), (select id from fy), 100000 + g, date '2026-01-01' + (g % 360), 'volumen', 'posted'
             from generate_series(1, 150000) g returning id)
insert into erp.journal_lines (company_id, entry_id, gl_account_id, debit, credit, line_no)
select (select cid from c), i.id, a.id, case when a.account_no = '57200001' then 10 else 0 end,
       case when a.account_no = '43000001' then 10 else 0 end, case when a.account_no = '57200001' then 1 else 2 end
from ins i cross join erp.gl_accounts a where a.company_id = (select cid from c) and a.account_no in ('57200001', '43000001');
set session_replication_role = origin;
analyze;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare c uuid := (select e from public.ctx where k = 'caso'); antes numeric := (select ms from public.tiempos where k = 'antes');
        despues numeric;
begin
  despues := least(public.medir(c), public.medir(c), public.medir(c));
  raise notice 'pantallas de la empresa pequeña: % ms antes, % ms con la otra empresa de 300.000 apuntes', round(antes), round(despues);
  assert despues < antes * 2 + 150,
         format('el tiempo de una empresa depende del tamaño de las demás: %s ms → %s ms', round(antes), round(despues));
  raise notice 'OK  · una empresa pequeña no se ralentiza por otra empresa grande en la misma base';
end $$;
reset role;

\echo 'FASE 72 OK'
