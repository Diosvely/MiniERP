-- =====================================================================
-- PRUEBAS FASE 70 · Rendimiento con empresas grandes en la base (migración 0076 · v0.52.1)
-- ---------------------------------------------------------------------
-- Regresión del error «La consulta ha tardado demasiado» en Comprobaciones y en Caso (Supabase, 28-10-2026).
-- Con el caso «Taller Atlántico SL» y, al lado, una empresa de OTRO usuario con 40.000 asientos:
--   · erp.audit_lines y las funciones de flujos ya no recorren los asientos ni los apuntes de toda la base;
--   · JIT apagado para la web (authenticated y anon) y para las funciones plpgsql del ERP;
--   · Comprobaciones y Caso responden lejos del límite de Supabase (8 s).
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
-- Los nodos del plan de una consulta (para saber si recorre una tabla entera)
create or replace function public.plan_nodes(q text) returns setof jsonb language plpgsql as $$
declare p jsonb;
begin
  execute 'explain (format json) ' || q into p;
  return query with recursive n(x) as (select p -> 0 -> 'Plan' union all select c from n, jsonb_array_elements(n.x -> 'Plans') c)
               select x from n;
end $$;
grant execute on function public.plan_nodes(text) to authenticated;

-- ---------- Datos: el caso (de a1) y una empresa grande de b2 ----------
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$ begin
  insert into public.ctx values ('caso', (erp.create_case_company('taller_atlantico', 'full')->>'company_id')::uuid);
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$ begin
  insert into public.ctx values ('grande', (erp.create_case_company('taller_atlantico', 'until_closing')->>'company_id')::uuid);
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', false) \gset

-- 40.000 asientos de la empresa grande, metidos directamente (sin disparadores: es solo volumen)
set session_replication_role = replica;
with c as (select e as cid from public.ctx where k = 'grande'),
     fy as (select id from erp.fiscal_years where company_id = (select cid from c) and year = 2026),
     ins as (insert into erp.journal_entries (company_id, fiscal_year_id, entry_no, posting_date, description, status)
             select (select cid from c), (select id from fy), 100000 + g, date '2026-01-01' + (g % 360), 'volumen', 'posted'
             from generate_series(1, 40000) g returning id)
insert into erp.journal_lines (company_id, entry_id, gl_account_id, debit, credit, line_no)
select (select cid from c), i.id, a.id, case when a.account_no = '62300001' then 10 else 0 end,
       case when a.account_no = '57200001' then 10 else 0 end, case when a.account_no = '62300001' then 1 else 2 end
from ins i cross join erp.gl_accounts a where a.company_id = (select cid from c) and a.account_no in ('62300001', '57200001');
set session_replication_role = origin;
analyze erp.journal_entries;
analyze erp.journal_lines;
analyze erp.gl_accounts;

-- ---------- Las consultas ya no recorren toda la base ----------
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare c uuid := (select e from public.ctx where k = 'caso'); q text;
begin
  q := format('select * from erp.audit_lines(%L, 2027, %L)', c, '2027-01-01');
  assert not exists (select 1 from public.plan_nodes(q) n
                     where n ->> 'Node Type' = 'Seq Scan' and n ->> 'Relation Name' in ('journal_entries', 'journal_lines')),
         'audit_lines no recorre los asientos ni los apuntes de toda la base';
  raise notice 'OK  · audit_lines busca por la empresa y por la clave del asiento';
end $$;
reset role;
do $$
declare c uuid := (select e from public.ctx where k = 'caso'); f text;
begin
  -- las de flujos son SECURITY DEFINER (sin seguridad fila a fila): el filtro por empresa es lo único que las acota
  foreach f in array array['cf_entry_cash', 'cf_cash'] loop
    assert not exists (select 1 from public.plan_nodes(format('select * from erp.%s(%L, 2026)', f, c)) n
                       where n ->> 'Node Type' = 'Seq Scan' and n ->> 'Relation Name' = 'journal_lines'),
           format('%s no recorre los apuntes de toda la base', f);
  end loop;
  raise notice 'OK  · las funciones de flujos filtran los apuntes por la empresa';
end $$;

-- ---------- JIT apagado ----------
do $$
begin
  assert exists (select 1 from pg_db_role_setting s join pg_roles r on r.oid = s.setrole
                 where r.rolname = 'authenticated' and 'jit=off' = any (s.setconfig)), 'authenticated sin JIT';
  assert exists (select 1 from pg_db_role_setting s join pg_roles r on r.oid = s.setrole
                 where r.rolname = 'anon' and 'jit=off' = any (s.setconfig)), 'anon sin JIT';
  assert not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace join pg_language l on l.oid = p.prolang
                     where n.nspname = 'erp' and l.lanname = 'plpgsql' and p.prokind = 'f'
                       and p.proname in ('run_audit_checks', 'case_compare', 'dashboard_data', 'integrity_checks', 'financial_ratios')
                       and not coalesce('jit=off' = any (p.proconfig), false)), 'las funciones pesadas, sin JIT';
  raise notice 'OK  · JIT apagado para la web y las funciones del ERP';
end $$;

-- ---------- Comprobaciones y Caso, rápidas aunque haya una empresa grande ----------
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare c uuid := (select e from public.ctx where k = 'caso'); t0 timestamptz; ms numeric; n int;
begin
  t0 := clock_timestamp();
  select count(*) into n from erp.run_audit_checks(c, 2027, '2027-01-01');
  ms := extract(epoch from clock_timestamp() - t0) * 1000;
  assert n > 0, 'las comprobaciones salen';
  assert ms < 4000, format('Comprobaciones tardan %s ms', round(ms));
  t0 := clock_timestamp();
  perform erp.case_compare(c, 'taller_atlantico');
  ms := extract(epoch from clock_timestamp() - t0) * 1000;
  assert ms < 4000, format('Caso tarda %s ms', round(ms));
  raise notice 'OK  · Comprobaciones y Caso, lejos del límite de 8 s de Supabase';
end $$;
reset role;

\echo 'FASE 70 OK'
