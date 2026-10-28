-- =====================================================================
-- PRUEBAS FASE 68 · Simulación con los asientos en edición (migración 0074 · v0.51.0)
-- ---------------------------------------------------------------------
-- Diseño validado por Diosvely (diseno-v0.51.0.md). Con el caso «Taller Atlántico SL» hasta antes del cierre:
--   · Sin simulación, los informes no cambian aunque haya borradores.
--   · Con simulación entra el borrador «en edición» y los informes (balance, PyG, sumas y saldos, mayor, flujos y
--     ratios) son EXACTAMENTE los que salen después de contabilizarlo.
--   · Un borrador «con error» (no cuadra) no entra nunca.
--   · La simulación vale solo para la consulta que la pide: el cierre, las comprobaciones, el contexto de la IA y el
--     puente a Power BI no la ven.
--   · No se puede preguntar por los borradores de otra empresa.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'owner@test.local'),
                                          ('00000000-0000-0000-0000-0000000000b2', 'otro@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);
create table public.ctx (k text primary key, e uuid);
grant all on public.ctx to authenticated;

-- Todos los informes de la web en una foto (jsonb) para comparar de una vez.
-- El mayor, sin el nº de asiento (el borrador aún no lo tiene); las comprobaciones de flujos, sin la lista de asientos.
create or replace function public.foto(c uuid, sim boolean) returns jsonb language sql as $$
  select jsonb_build_object(
    'balance',  (select jsonb_agg(to_jsonb(x) order by x.sort) from erp.financial_statement(c, 2026, 'balance', null, sim) x),
    'pyg',      (select jsonb_agg(to_jsonb(x) order by x.sort) from erp.financial_statement(c, 2026, 'pyg', null, sim) x),
    'pyg_dic',  (select jsonb_agg(to_jsonb(x) order by x.sort) from erp.financial_statement(c, 2026, 'pyg', '2026-12-31', sim) x),
    'cuentas',  (select jsonb_agg(to_jsonb(x) order by x.account_no) from erp.fs_line_accounts(c, 2026, 'pyg', 'PA', null, sim) x),
    'sumas',    (select jsonb_agg(to_jsonb(x) order by x.account_no) from erp.trial_balance(c, 2026, null, null, sim) x),
    'sumas3',   (select jsonb_agg(to_jsonb(x) order by x.account_no) from erp.trial_balance(c, 2026, 3, null, sim) x),
    'anomalias',(select coalesce(jsonb_agg(to_jsonb(x) order by x.account_no), '[]') from erp.balance_anomalies(c, 2026, null, null, sim) x),
    'mayor',    (select jsonb_agg(to_jsonb(x) - 'entry_no') from erp.general_ledger(c, 2026, '57200001', null, sim) x),
    'mayor625', (select coalesce(jsonb_agg(to_jsonb(x) - 'entry_no'), '[]') from erp.general_ledger(c, 2026, '62500001', null, sim) x),
    'efe_ind',  (select jsonb_agg(to_jsonb(x) order by x.sort) from erp.cash_flow_statement(c, 2026, 'indirect', sim) x),
    'efe_dir',  (select jsonb_agg(to_jsonb(x) order by x.sort) from erp.cash_flow_statement(c, 2026, 'direct', sim) x),
    'efe_ctas', (select jsonb_agg(to_jsonb(x) order by x.account_no) from erp.cf_line_accounts(c, 2026, 'indirect', 'IA', sim) x),
    'efe_chk',  erp.cash_flow_check(c, 2026, sim) - 'cross_entries',
    'ratios',   (select jsonb_agg(to_jsonb(x) order by x.code) from erp.financial_ratios(c, 2026, sim) x));
$$;
grant execute on function public.foto(uuid, boolean) to authenticated;
create table public.fotos (k text primary key, f jsonb);
grant all on public.fotos to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare c uuid; a uuid; ej uuid;
begin
  c := (erp.create_case_company('taller_atlantico', 'until_closing')->>'company_id')::uuid;
  insert into public.ctx values ('c', c);
  ej := (select id from erp.fiscal_years where company_id = c and year = 2026);
  insert into public.fotos values ('antes', public.foto(c, false));
  assert public.foto(c, true) = (select f from public.fotos where k = 'antes'),
         'sin borradores, la simulación no cambia nada';
  assert erp.report_drafts(c, 2026) = 0, 'sin borradores, 0 en la franja';

  -- El borrador «en edición»: el seguro de diciembre, pagado por el banco
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (c, ej, '2026-12-20', 'Seguro de diciembre (borrador)') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit)
  values (a, (select id from erp.gl_accounts where company_id = c and account_no = '62500001'), 300);
  insert into erp.journal_lines (entry_id, gl_account_id, credit)
  values (a, (select id from erp.gl_accounts where company_id = c and account_no = '57200001'), 300);
  insert into public.ctx values ('bueno', a);
  -- El borrador «con error»: no cuadra
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (c, ej, '2026-12-21', 'Asesoría (borrador que no cuadra)') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit)
  values (a, (select id from erp.gl_accounts where company_id = c and account_no = '62300001'), 100);
  insert into erp.journal_lines (entry_id, gl_account_id, credit)
  values (a, (select id from erp.gl_accounts where company_id = c and account_no = '57200001'), 90);
  insert into public.ctx values ('malo', a);
end $$;
reset role;
do $$
begin
  assert erp.draft_problem((select e from public.ctx where k = 'bueno')) is null, 'el seguro está «en edición»';
  assert erp.draft_problem((select e from public.ctx where k = 'malo')) = 'unbalanced', 'el de asesoría, «con error»';
end $$;
set role authenticated;

do $$
declare c uuid := (select e from public.ctx where k = 'c'); antes jsonb := (select f from public.fotos where k = 'antes');
        s jsonb;
begin
  -- ---------- Sin simulación, nada cambia ----------
  assert public.foto(c, false) = antes, 'sin simulación, los informes no ven los borradores';
  -- La llamada de siempre, sin el parámetro nuevo (la que hacen el cierre, la IA…)
  assert (select jsonb_agg(to_jsonb(x) order by x.sort) from erp.financial_statement(c, 2026, 'balance') x) = antes->'balance';
  assert (select jsonb_agg(to_jsonb(x) order by x.account_no) from erp.trial_balance(c, 2026) x) = antes->'sumas';
  raise notice 'OK  · sin simulación, los informes son los de siempre aunque haya borradores';

  -- ---------- Con simulación ----------
  s := public.foto(c, true);
  insert into public.fotos values ('sim', s);
  assert s <> antes, 'con simulación, el borrador cambia los informes';
  assert erp.report_drafts(c, 2026) = 1, 'la franja: 1 asiento en edición (el que no cuadra no cuenta)';
  assert erp.report_drafts(c, 2026, '2026-11-30') = 0, 'hasta noviembre, ninguno';
  assert jsonb_array_length(s->'mayor625') = jsonb_array_length(antes->'mayor625') + 1, 'el mayor de la 625 trae el borrador';
  assert (s->'mayor625'->-1->>'debit')::numeric = 300 and (s->'mayor625'->-1->>'description') = 'Seguro de diciembre (borrador)';
  assert jsonb_array_length(s->'mayor') = jsonb_array_length(antes->'mayor') + 1,
         'el mayor del banco trae el seguro, pero no la asesoría que no cuadra';
  assert not exists (select 1 from erp.general_ledger(c, 2026, '62300001', null, true) x where x.description like 'Asesoría (borrador%'),
         'el borrador con error no entra nunca';
  assert (select x.total_debit from erp.trial_balance(c, 2026, null, null, true) x where x.account_no = '62500001')
       = (select x.total_debit from erp.trial_balance(c, 2026) x where x.account_no = '62500001') + 300, 'sumas y saldos: +300 en la 625';
  assert (select x.amount from erp.financial_statement(c, 2026, 'pyg', null, true) x where x.code = 'PA')
       = (select x.amount from erp.financial_statement(c, 2026, 'pyg') x where x.code = 'PA') - 300, 'PyG: el resultado baja 300';
  assert (s->'efe_chk'->>'balanced')::boolean, 'el estado de flujos simulado cuadra con la tesorería';
  assert (s->'efe_chk'->>'cash_change')::numeric = (antes->'efe_chk'->>'cash_change')::numeric - 300, 'flujos: la caja baja 300';
  raise notice 'OK  · con simulación entra el borrador «en edición» y no el «con error»';

  -- ---------- La simulación vale solo para su consulta ----------
  assert not erp.simulating(), 'al terminar el informe, la simulación se apaga';
  assert (select jsonb_agg(to_jsonb(x) order by x.sort) from erp.financial_statement(c, 2026, 'balance') x) = antes->'balance',
         'la siguiente consulta sin simulación ya no ve el borrador';
  perform set_config('erp.simulate', 'on', true);
  assert (select jsonb_agg(to_jsonb(x) order by x.sort) from erp.financial_statement(c, 2026, 'balance', null, true) x) = s->'balance';
  assert erp.simulating(), 'una llamada interna deja el ajuste como lo encontró';
  perform set_config('erp.simulate', 'off', true);
  raise notice 'OK  · la simulación se enciende y se apaga en cada informe';
end $$;

-- ---------- Lo que nunca usa borradores ----------
do $$
declare c uuid := (select e from public.ctx where k = 'c'); p1 jsonb; p2 jsonb; i1 jsonb; i2 jsonb;
begin
  p1 := to_jsonb(erp.year_closing_preview(c, 2026));
  i1 := (select jsonb_agg(to_jsonb(x)) from erp.integrity_checks(c, 2026) x);
  perform public.foto(c, true);   -- un informe simulado en la misma transacción
  p2 := to_jsonb(erp.year_closing_preview(c, 2026));
  i2 := (select jsonb_agg(to_jsonb(x)) from erp.integrity_checks(c, 2026) x);
  assert p1 = p2, 'la vista previa del cierre no ve los borradores';
  assert i1 = i2, 'las comprobaciones de integridad no ven los borradores';
  raise notice 'OK  · el cierre y las comprobaciones no ven la simulación';
end $$;

-- ---------- Otra empresa no puede preguntar por mis borradores ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
begin
  assert not erp.draft_ready((select e from public.ctx where k = 'bueno')), 'de otra empresa no se sabe nada';
  assert erp.report_drafts((select e from public.ctx where k = 'c'), 2026) = 0, 'ni cuántos borradores tiene';
  assert not exists (select 1 from erp.trial_balance((select e from public.ctx where k = 'c'), 2026, null, null, true)),
         'ni sus sumas y saldos';
  raise notice 'OK  · los borradores de otra empresa no se ven';
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

-- ---------- Contabilizado, sale lo mismo que en la simulación ----------
do $$
declare c uuid := (select e from public.ctx where k = 'c'); s jsonb := (select f from public.fotos where k = 'sim');
begin
  perform erp.post_entry((select e from public.ctx where k = 'bueno'));
  delete from erp.journal_entries where id = (select e from public.ctx where k = 'malo');
  assert public.foto(c, false) = s, 'después de contabilizarlo, los informes son los de la simulación';
  assert public.foto(c, true) = s, 'y con la casilla marcada, igual (ya no hay borradores)';
  assert erp.report_drafts(c, 2026) = 0;
  raise notice 'OK  · la simulación coincide con el resultado de contabilizar el asiento';
end $$;
reset role;

-- ---------- Permisos ----------
do $$
begin
  assert not has_function_privilege('anon', 'erp.financial_statement(uuid, integer, text, date, boolean)', 'execute');
  assert has_function_privilege('authenticated', 'erp.financial_statement(uuid, integer, text, date, boolean)', 'execute');
  assert has_function_privilege('authenticated', 'erp.report_drafts(uuid, integer, date)', 'execute');
  assert not has_function_privilege('authenticated', 'erp.draft_problem(uuid)', 'execute'), 'draft_problem sigue cerrada';
  assert not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'erp' and p.proname in ('financial_statement', 'trial_balance', 'general_ledger',
                       'fs_line_accounts', 'balance_anomalies', 'cash_flow_statement', 'cash_flow_check',
                       'cf_line_accounts', 'financial_ratios')
                     group by p.proname having count(*) > 1), 'una sola firma de cada informe (la API no se lía)';
  raise notice 'OK  · permisos y firmas';
end $$;

\echo 'FASE 68 OK'
