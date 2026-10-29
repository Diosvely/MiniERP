-- =====================================================================
-- PRUEBAS FASE 71 · Empresas grandes de varios años (migración 0077 · v0.52.2)
-- ---------------------------------------------------------------------
-- Regresión: Comprobaciones superaba el límite de 8 s de Supabase en empresas grandes (28/29-10-2026).
-- Con el caso «Taller Atlántico SL» hasta antes del cierre y 15.000 asientos manuales más en 2026:
--   · Comprobaciones responde lejos del límite (antes, unos 15 s con este volumen);
--   · la comprobación de cuentas controladas encuentra los mismos asientos que asiento por asiento;
--   · el permiso se comprueba una vez y sigue funcionando: otra persona no ve nada; el administrador de la base, todo.
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
  insert into public.ctx values ('c', (erp.create_case_company('taller_atlantico', 'until_closing')->>'company_id')::uuid);
end $$;
reset role;

-- 15.000 asientos manuales más (cobros de clientes: tocan la 430, que es una cuenta controlada), sin disparadores
set session_replication_role = replica;
with c as (select e as cid from public.ctx where k = 'c'),
     fy as (select id from erp.fiscal_years where company_id = (select cid from c) and year = 2026),
     ins as (insert into erp.journal_entries (company_id, fiscal_year_id, entry_no, posting_date, description, status)
             select (select cid from c), (select id from fy), 100000 + g, date '2026-01-01' + (g % 360), 'Cobro manual', 'posted'
             from generate_series(1, 15000) g returning id)
insert into erp.journal_lines (company_id, entry_id, gl_account_id, debit, credit, line_no)
select (select cid from c), i.id, a.id, case when a.account_no = '57200001' then 10 else 0 end,
       case when a.account_no = '43000001' then 10 else 0 end, case when a.account_no = '57200001' then 1 else 2 end
from ins i cross join erp.gl_accounts a where a.company_id = (select cid from c) and a.account_no in ('57200001', '43000001');
set session_replication_role = origin;
analyze erp.journal_entries;
analyze erp.journal_lines;

-- ---------- Rápida ----------
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare c uuid := (select e from public.ctx where k = 'c'); t0 timestamptz; ms numeric; ctl record; n int;
begin
  t0 := clock_timestamp();
  select * into ctl from erp.run_audit_checks(c, 2026, '2026-12-31') x where x.code = 'controlled';
  ms := extract(epoch from clock_timestamp() - t0) * 1000;
  assert ms < 5000, format('Comprobaciones tardan %s ms', round(ms));
  raise notice 'OK  · Comprobaciones con 15.000 asientos más: % ms', round(ms);

  -- La comprobación en bloque encuentra lo mismo que la de siempre, asiento por asiento
  select count(*) into n
  from (select distinct a.entry_id from erp.audit_lines(c, 2026, '2026-12-31') a where a.source = 'manual' and a.entry_id = a.k) m
  where jsonb_array_length(erp.entry_controlled_lines(m.entry_id)) > 0
    and not exists (select 1 from erp.journal_entries x where x.reversal_of = m.entry_id and x.status = 'posted')
    and not exists (select 1 from erp.payments py where py.entry_id = m.entry_id and py.linked);
  assert ctl.items = n and n >= 15000, format('controladas: %s en bloque, %s asiento por asiento', ctl.items, n);
  assert ctl.details -> 0 ->> 'account_no' = '43000001' and ctl.details -> 0 -> 'modules' is not null;
  assert jsonb_array_length(ctl.details) = 50, 'el detalle, los 50 primeros';
  raise notice 'OK  · cuentas controladas: los mismos % asientos que asiento por asiento', n;
end $$;

-- ---------- El permiso, una vez ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare c uuid := (select e from public.ctx where k = 'c');
begin
  assert not exists (select 1 from erp.audit_lines(c, 2026)), 'otra persona: sin apuntes';
  assert not exists (select 1 from erp.trial_balance(c, 2026)), 'ni sumas y saldos';
  assert not exists (select 1 from erp.general_ledger(c, 2026, '57200001')), 'ni mayor';
  assert not exists (select 1 from erp.fs_classified_at(c, 2026, 'balance', array[null::date])), 'ni balance';
  assert not erp.can_report(c);
  raise notice 'OK  · otra persona no ve nada';
end $$;
reset role;
do $$
declare c uuid := (select e from public.ctx where k = 'c');
begin
  assert erp.can_report(c) and exists (select 1 from erp.trial_balance(c, 2026)), 'el administrador de la base lo ve todo';
  assert (select prosecdef from pg_proc where oid = 'erp.audit_lines(uuid, integer, date)'::regprocedure), 'audit_lines comprueba el permiso una vez';
  raise notice 'OK  · el administrador de la base lo ve, como con la seguridad fila a fila';
end $$;

\echo 'FASE 71 OK'
