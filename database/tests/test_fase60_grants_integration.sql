-- =====================================================================
-- PRUEBAS FASE 60 · Subvenciones integradas (migración 0065 · v0.44.0)
-- ---------------------------------------------------------------------
-- Supuestos de referencia: supuestos-v0.44.0.md.
--   S4  ECPN de 2026: patrimonio neto inicial 78.000 (capital 60.000, reservas 10.000 y el resultado de 2025, 8.000,
--       que la junta lleva a reservas); resultado de 2026, 30.000; subvención S1 → parte A: 30.000 + 15.000 − 1.500 =
--       43.500; parte B: capital 60.000 · reservas 18.000 · resultado 30.000 · subvenciones 13.500 = 121.500, igual que
--       el balance
--   El cierre de 2026 regulariza los grupos 8 y 9 contra la 130 (13.500) y la apertura de 2027 la lleva
--   S1b con la baja desde Inmovilizado: lo que queda pasa a resultados; al anular la baja, se deshace
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local'),
                                          ('00000000-0000-0000-0000-0000000000b2', 'otro@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);
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
create or replace function public.empresa(nombre text) returns uuid language plpgsql as $$
declare e uuid; c text;
begin
  insert into erp.companies (name, industry, tax_territory, created_by) values (nombre, 'services', 'mainland', auth.uid()) returning id into e;
  perform erp.create_fiscal_year(e, 2026); perform erp.create_fiscal_year(e, 2027); perform erp.create_fiscal_year(e, 2028);
  perform erp.setup_taxes(e);
    foreach c in array array['57200001:Banco', '70500001:Prestación de servicios', '62900001:Otros servicios', '41000001:Acreedores'] loop
    if not exists (select 1 from erp.gl_accounts where company_id = e and account_no = split_part(c, ':', 1)) then
      perform erp.create_posting_account(e, split_part(c, ':', 1), split_part(c, ':', 2));
    end if;
  end loop;
  return e;
end $$;
create or replace function public.manual(e uuid, d date, l jsonb) returns void language plpgsql as $$
declare a uuid; x jsonb;
begin
  for x in select * from jsonb_array_elements(l) loop   -- las cuentas que falten (113, 112…), se crean
    if not exists (select 1 from erp.gl_accounts where company_id = e and account_no = x->>0) then
      perform erp.create_posting_account(e, x->>0, 'Cuenta ' || (x->>0));
    end if;
  end loop;
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and year = extract(year from d)), d, 'Supuesto') returning id into a;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit)
  select a, e, x.ord, (select id from erp.gl_accounts where company_id = e and account_no = x.v->>0), (x.v->>1)::numeric, (x.v->>2)::numeric
  from jsonb_array_elements(l) with ordinality as x(v, ord);
  perform erp.post_entry(a);
end $$;
create or replace function public.lineas(p_entry uuid) returns text language sql as $$
  select string_agg(left(g.account_no, 4) || case when l.debit <> 0 then ' D ' || l.debit else ' H ' || l.credit end, ' | ' order by g.account_no, l.debit)
  from erp.journal_lines l join erp.gl_accounts g on g.id = l.gl_account_id where l.entry_id = p_entry and g.account_no ~ '^(13|479|8|9)';
$$;
create or replace function public.resp(t text) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('account_no', p[1], 'debit', case p[2] when 'D' then p[3]::numeric else 0 end,
                                      'credit', case p[2] when 'H' then p[3]::numeric else 0 end) order by ord)
  from unnest(string_to_array(t, ' | ')) with ordinality u(x, ord), string_to_array(u.x, ' ') p;
$$;
create or replace function public.asiento(p_grant uuid, p_kind text) returns text language sql as $$
  select string_agg(left(g.account_no, 4) || case when l.debit <> 0 then ' D ' || l.debit else ' H ' || l.credit end, ' | ' order by l.line_no)
  from erp.journal_lines l join erp.gl_accounts g on g.id = l.gl_account_id
  where l.entry_id = (select v.entry_id from erp.grant_events v where v.grant_id = p_grant and v.kind = p_kind and v.status = 'posted' order by v.seq desc limit 1);
$$;
create or replace function public.saldo(e uuid, pref text, d date) returns numeric language sql as $$
  select coalesce(sum(l.credit - l.debit), 0) from erp.journal_lines l join erp.journal_entries j on j.id = l.entry_id
  join erp.gl_accounts g on g.id = l.gl_account_id where j.company_id = e and j.status = 'posted' and j.posting_date <= d and g.account_no like pref || '%';
$$;
create or replace function public.activo(e uuid, coste numeric, meses int, inicio date) returns uuid language sql as $$
  select asset_id from erp.create_fixed_asset(jsonb_build_object('company_id', e, 'name', 'Máquina', 'asset_account_no', '21300001',
         'cost', coste, 'useful_life_months', meses, 'start_date', inicio));
$$;
create or replace function public.sub(e uuid, extra jsonb) returns uuid language sql as $$
  select (erp.grant_create(jsonb_build_object('company_id', e, 'kind', 'capital', 'description', 'Subvención de prueba', 'grantor', 'Gobierno de Canarias') || extra)->>'grant_id')::uuid $$;
grant execute on function public.falla(text, text), public.empresa(text), public.manual(uuid, date, jsonb), public.asiento(uuid, text),
  public.saldo(uuid, text, date), public.activo(uuid, numeric, int, date), public.sub(uuid, jsonb), public.lineas(uuid), public.resp(text) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

-- ---------- Glosario, cuentas controladas, auditor y Practicar ----------
do $$
declare g jsonb;
begin
  assert (select count(*) from erp.concepts where key in ('capitalGrant', 'refundableGrant', 'groupsEightNine', 'equityStatement')) = 4, 'glosario';
  assert (select count(*) from erp.control_rules where modules = '{grants}') = 4, 'cuentas controladas: 94, 84, 83, 4708';
  assert not exists (select 1 from erp.control_rules where account_prefix in ('130', '172', '522')), 'la apertura necesita la 130, la 172 y la 522';
  assert (select screen from erp.audit_checks where code = 'grants_ledger') = 'grants' and (select screen from erp.operations where key = 'capital_grant') = 'grants';
  g := erp.grade_exercise('capital_grant_imputation', public.resp('84000001 D 2000 | 74600001 H 2000 | 47900001 D 500 | 83010001 H 500'));
  assert (g->>'ok')::boolean and (g->>'score')::int = 100, g::text;
  g := erp.grade_exercise('capital_grant_imputation', public.resp('130 D 2000 | 746 H 2000 | 479 D 500 | 8301 H 500'));
  assert not (g->>'ok')::boolean and exists (select 1 from jsonb_array_elements(g->'tips') t where t->>'msg' like 'La 130 no se toca%'), g::text;
  g := erp.grade_exercise('capital_grant_concession', public.resp('4708 D 20000 | 940 H 20000 | 8301 D 5000 | 479 H 5000'));
  assert (g->>'ok')::boolean, g::text;
  raise notice 'OK  · glosario (4), 4 cuentas controladas, comprobación del auditor, operaciones y supuestos de Practicar';
end $$;

-- ---------- S4 · El año 2026 completo y su ECPN ----------
do $$
declare e uuid := public.empresa('ECPN SL'); a uuid; g uuid; x jsonb;
begin
  insert into public.ctx values ('s4', e);
  perform erp.set_control_mode(e, 'guided');
  perform erp.create_fiscal_year(e, 2025);
  perform public.manual(e, '2025-01-02', '[["57200001", 70000, 0], ["10000001", 0, 60000], ["11300001", 0, 10000]]');
  perform public.manual(e, '2025-12-15', '[["57200001", 8000, 0], ["70500001", 0, 8000]]');
  perform erp.close_fiscal_year(e, 2025, true);
  -- 2026: la junta lleva el resultado de 2025 a reservas (800 a la legal y 7.200 a voluntarias)
  perform erp.equity_distribution(jsonb_build_object('company_id', e, 'date', '2026-06-30', 'dividend', 0));
  perform erp.create_posting_account(e, '21300001', 'Maquinaria');
  a := public.activo(e, 50000, 120, '2026-01-01');
  perform public.manual(e, '2026-01-01', '[["21300001", 50000, 0], ["57200001", 0, 50000]]');
  g := public.sub(e, jsonb_build_object('amount', 20000, 'date', '2026-03-15', 'asset_id', a));
  perform erp.grant_collect(jsonb_build_object('grant_id', g, 'date', '2026-06-30'));
  perform public.manual(e, '2026-11-30', '[["57200001", 33000, 0], ["70500001", 0, 33000]]');
  perform erp.post_depreciation(e, '2026-12-31');
  -- el asistente: la imputación de las subvenciones está pendiente (paso 10)
  assert (select status || '/' || step from erp.closing_checklist(e, 2026) where code = 'grants') = 'pending/10', 'asistente: subvenciones pendientes';
  assert exists (select 1 from jsonb_array_elements(erp.year_closing_preview(e, 2026)->'checks') c where c->>'code' = 'grants_not_imputed'), 'aviso del cierre';
  perform erp.grant_year_end(e, '2026-12-31');
  assert (select string_agg(step || ':' || code || '=' || status, ' ' order by step) from erp.closing_checklist(e, 2026) where step >= 9)
       like '9:financing=na 10:grants=done 11:audit_checks=% 12:corporate_tax=% 13:close=pending', 'pasos del asistente';
  -- ECPN, parte A
  x := erp.equity_statement(e, 2026);
  assert (x->'part_a'->>'result')::numeric = 30000 and (x->'part_a'->>'b_grants')::numeric = 20000 and (x->'part_a'->>'b_tax')::numeric = -5000
     and (x->'part_a'->>'b_total')::numeric = 15000 and (x->'part_a'->>'c_grants')::numeric = -2000 and (x->'part_a'->>'c_tax')::numeric = 500
     and (x->'part_a'->>'c_total')::numeric = -1500 and (x->'part_a'->>'total')::numeric = 43500, 'parte A: ' || (x->'part_a')::text;
  -- ECPN, parte B
  assert (x->'part_b'->'start'->>'capital')::numeric = 60000 and (x->'part_b'->'start'->>'reserves')::numeric = 10000
     and (x->'part_b'->'start'->>'result')::numeric = 8000 and (x->>'start')::numeric = 78000, 'saldo inicial: ' || (x->'part_b'->'start')::text;
  assert (x->'part_b'->'other'->>'reserves')::numeric = 8000 and (x->'part_b'->'other'->>'result')::numeric = -8000, 'distribución del resultado: ' || (x->'part_b'->'other')::text;
  assert (x->'part_b'->'recognised'->>'result')::numeric = 30000 and (x->'part_b'->'recognised'->>'grants')::numeric = 13500, 'reconocidos: ' || (x->'part_b'->'recognised')::text;
  assert coalesce((x->'part_b'->'owners'->>'result')::numeric, 0) = 0, 'sin dividendos';
  assert (x->>'end')::numeric = 121500 and (x->>'balance_net_worth')::numeric = 121500 and (x->>'ok')::boolean, 'saldo final = balance: ' || x::text;
  assert x->'columns' = '["capital", "reserves", "result", "grants"]'::jsonb, 'columnas: ' || (x->'columns')::text;
  raise notice 'OK  · S4: ECPN de 2026, parte A 43.500 (30.000 + 15.000 − 1.500) y parte B 78.000 → 121.500, igual que el balance';
end $$;

-- ---------- El cierre de 2026: los grupos 8 y 9, contra la 130 ----------
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 's4'); r record; x jsonb;
begin
  select * into r from erp.close_fiscal_year(e, 2026, true);
  assert public.lineas((select closing_pl_entry_id from erp.year_closings where company_id = e and year = 2026 and status = 'posted'))
       = '1300 H 13500.00 | 8301 H 4500.00 | 8400 H 2000.00 | 9400 D 20000.00',
       'regularización: ' || public.lineas((select closing_pl_entry_id from erp.year_closings where company_id = e and year = 2026 and status = 'posted'));
  assert public.lineas((select opening_entry_id from erp.year_closings where company_id = e and year = 2026 and status = 'posted')) = '1300 H 13500.00 | 4790 H 4500.00',
         'apertura de 2027: ' || public.lineas((select opening_entry_id from erp.year_closings where company_id = e and year = 2026 and status = 'posted'));
  x := erp.equity_statement(e, 2027);
  assert (x->'part_b'->'start'->>'grants')::numeric = 13500 and (x->>'start')::numeric = 121500 and (x->>'ok')::boolean, 'ECPN de 2027: ' || x::text;
  assert (select sum(amount) from erp.fs_classified_accounts(e, 2027, 'balance', '2027-01-01') where line_code = 'PN.A2') = 13500, 'balance de 2027: A-2';
  execute 'set constraints all immediate'; execute 'set constraints all deferred';
  assert (select status from erp.run_audit_checks(e, 2027, '2027-01-01') where code = 'grants_ledger') = 'ok', 'auditor: la regularización cuenta como del módulo';
  raise notice 'OK  · cierre de 2026: regularización de los grupos 8 y 9 contra la 130 (13.500) y apertura de 2027 con la 130 y la 479';
end $$;

-- ---------- S1b · Baja del activo desde Inmovilizado ----------
do $$
declare e uuid := public.empresa('Baja SL'); a uuid; g uuid; r record;
begin
  perform erp.create_posting_account(e, '21300001', 'Maquinaria');
  a := public.activo(e, 50000, 120, '2026-01-01');
  g := public.sub(e, jsonb_build_object('amount', 20000, 'date', '2026-03-15', 'asset_id', a));
  perform erp.post_depreciation(e, '2026-12-31'); perform erp.grant_year_end(e, '2026-12-31');
  select * into r from erp.dispose_asset(jsonb_build_object('asset_id', a, 'disposal_date', '2027-12-31'));
  assert (select status from erp.grants where id = g) = 'imputed', 'la baja imputa la subvención';
  assert public.asiento(g, 'disposal') = '8400 D 18000.00 | 7460 H 18000.00 | 4790 D 4500.00 | 8301 H 4500.00', 'lo pendiente: ' || public.asiento(g, 'disposal');
  assert public.saldo(e, '479', '2027-12-31') = 0, 'la 479 a cero';
  perform erp.cancel_disposal(a);
  assert (select status from erp.grants where id = g) = 'active' and public.saldo(e, '479', '2027-12-31') = 4500, 'anular la baja la deshace';
  raise notice 'OK  · S1b: la baja del activo pasa a resultados lo que queda de la subvención (18.000) y anularla lo deshace';
end $$;

-- ---------- Sin subvenciones: no aplica, y el ECPN de una empresa cualquiera ----------
do $$
declare e uuid := public.empresa('Sin subvenciones SL'); x jsonb;
begin
  perform public.manual(e, '2026-01-02', '[["57200001", 3000, 0], ["10000001", 0, 3000]]');
  assert (select status from erp.closing_checklist(e, 2026) where code = 'grants') = 'na', 'no aplica';
  x := erp.equity_statement(e, 2026);
  assert (x->>'start')::numeric = 0 and (x->'part_b'->'other'->>'capital')::numeric = 3000 and (x->>'end')::numeric = 3000 and (x->>'ok')::boolean, 'ECPN sencillo: ' || x::text;
  raise notice 'OK  · sin subvenciones el paso no aplica; el ECPN de una empresa sin grupos 8 y 9 también cuadra';
end $$;

-- ---------- Seguridad ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 's4');
begin
  assert public.falla(format('select erp.equity_statement(%L, 2026)', e), 'No permission'), 'otro usuario no ve el ECPN';
  assert public.falla(format('select * from erp.equity_statement_lines(%L, 2026)', e), 'permission denied'), 'las líneas no son públicas';
  raise notice 'OK  · otro usuario no ve el ECPN de una empresa ajena';
end $$;

\echo '✔ FASE 60 OK · Subvenciones integradas: cierre de los grupos 8 y 9, baja del activo, ECPN, asistente, auditor y Practicar'
