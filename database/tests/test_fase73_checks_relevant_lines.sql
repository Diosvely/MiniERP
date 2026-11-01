-- =====================================================================
-- PRUEBAS FASE 73 · Comprobaciones lee solo los apuntes que necesita (migración 0079 · v0.52.4)
-- ---------------------------------------------------------------------
-- erp.audit_lines_checks devuelve exactamente los apuntes de erp.audit_lines que usan las comprobaciones (cuentas 47,
-- con código de impuesto y asientos manuales), con el mismo origen; y en una empresa con muchos apuntes que no son de
-- la 47 lee muchos menos. Los permisos, como erp.audit_lines.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'owner@test.local'),
                                          ('00000000-0000-0000-0000-0000000000b2', 'otro@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);
create table public.ctx (k text primary key, e uuid);
grant all on public.ctx to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$ begin
  insert into public.ctx values ('c', (erp.create_case_company('taller_atlantico', 'full')->>'company_id')::uuid);
end $$;

do $$
declare c uuid := (select e from public.ctx where k = 'c'); y int; a text; b text; n_all int; n_chk int;
begin
  foreach y in array array[2026, 2027] loop
    select md5(coalesce(string_agg(x::text, '|' order by x::text), '')), count(*) into a, n_chk from erp.audit_lines_checks(c, y) x;
    select md5(coalesce(string_agg(row(x.*)::text, '|' order by row(x.*)::text), '')) into b
    from erp.audit_lines(c, y) x where x.account_no like '47%' or x.tax_code is not null or x.source = 'manual';
    assert a = b, format('%s: audit_lines_checks no coincide con los apuntes de audit_lines que usan las comprobaciones', y);
  end loop;
  select count(*) into n_all from erp.audit_lines(c, 2026);
  select count(*) into n_chk from erp.audit_lines_checks(c, 2026);
  assert n_chk > 0 and n_chk <= n_all;
  assert (select count(distinct x.source) from erp.audit_lines_checks(c, 2026) x) >= 5, 'con sus orígenes (factura, pago, manual…)';
  raise notice 'OK  · los mismos apuntes y orígenes que audit_lines, solo los que usan las comprobaciones (% de %)', n_chk, n_all;
end $$;

-- Empresa importada: casi todo fuera de la 47 → lee mucho menos
reset role;
set session_replication_role = replica;
with c as (select e as cid from public.ctx where k = 'c'),
     fy as (select id from erp.fiscal_years where company_id = (select cid from c) and year = 2027),
     ins as (insert into erp.journal_entries (company_id, fiscal_year_id, entry_no, posting_date, description, status, import_batch_id)
             select (select cid from c), (select id from fy), 100000 + g, date '2027-01-01' + (g % 300), 'cobro importado', 'posted', null
             from generate_series(1, 2000) g returning id)
insert into erp.journal_lines (company_id, entry_id, gl_account_id, debit, credit, line_no)
select (select cid from c), i.id, a.id, case when a.account_no = '57200001' then 10 else 0 end,
       case when a.account_no = '43000001' then 10 else 0 end, case when a.account_no = '57200001' then 1 else 2 end
from ins i cross join erp.gl_accounts a where a.company_id = (select cid from c) and a.account_no in ('57200001', '43000001');
-- que parezcan importados (sin disparadores: es solo volumen)
update erp.journal_entries set import_batch_id = gen_random_uuid() where description = 'cobro importado';
set session_replication_role = origin;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare c uuid := (select e from public.ctx where k = 'c'); n_all int; n_chk int;
begin
  select count(*) into n_all from erp.audit_lines(c, 2027);
  select count(*) into n_chk from erp.audit_lines_checks(c, 2027);
  assert n_all >= 4000 and n_chk = 0, format('importada sin cuentas 47: %s de %s', n_chk, n_all);
  raise notice 'OK  · empresa importada: lee % apuntes de %', n_chk, n_all;
end $$;

-- Permisos: otra persona no ve nada
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
begin
  assert not exists (select 1 from erp.audit_lines_checks((select e from public.ctx where k = 'c'), 2026)), 'otra persona: nada';
  raise notice 'OK  · otra persona no ve nada';
end $$;
reset role;
do $$ begin
  assert exists (select 1 from pg_indexes where indexname = 'journal_lines_company_tax');
  assert not has_function_privilege('anon', 'erp.audit_lines_checks(uuid, integer, date)', 'execute');
end $$;

\echo 'FASE 73 OK'
