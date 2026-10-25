-- =====================================================================
-- PRUEBAS FASE 59 · Subvenciones (migración 0064 · v0.44.0)
-- ---------------------------------------------------------------------
-- Supuestos de referencia calculados a mano desde el PGC antes de programar (docs del proyecto: supuestos-v0.44.0.md).
--   S1  Subvención de capital de 20.000 para una máquina de 50.000 (10 años): concesión 4708 / 940 + 8301 5.000 / 479;
--       cobro; cada año 840 / 746 2.000 y 479 / 8301 500
--   S1b Venta de la máquina al final de 2028: lo pendiente (14.000) a resultados, y la 479 (3.500) a cero
--   S2  Subvención a la explotación de 3.000: 4708 / 740, sin grupos 8 y 9
--   S3  Reintegrable de 10.000 cobrada (572 / 522) que deja de serlo el 31/03/2027 (522 / 940 + 8301 / 479 2.500);
--       imputación de 2027: el 15 % (4.500 de 30.000 amortizados) → 1.500 y 375
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
  public.saldo(uuid, text, date), public.activo(uuid, numeric, int, date), public.sub(uuid, jsonb) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

-- ---------- Plantilla: grupos 8 y 9 ----------
do $$
declare e uuid := public.empresa('Plantilla SL');
begin
  assert (select count(*) from erp.gl_accounts where company_id = e and account_no in ('8', '84', '840', '8301', '9', '94', '940', '522')) = 8, 'grupos 8 y 9 y la 522';
  raise notice 'OK  · los grupos 8 y 9 y la 522 están en el plan de cuentas';
end $$;

-- ---------- S1 · Subvención de capital no reintegrable ----------
do $$
declare e uuid := public.empresa('Subvenciones SL'); a uuid; g uuid; x jsonb;
begin
  insert into public.ctx values ('s1', e);
  perform erp.create_posting_account(e, '21300001', 'Maquinaria');
  a := public.activo(e, 50000, 120, '2026-01-01');
  g := public.sub(e, jsonb_build_object('amount', 20000, 'date', '2026-03-15', 'asset_id', a));
  insert into public.ctx values ('s1g', g);
  assert public.asiento(g, 'concession') = '4708 D 20000.00 | 9400 H 20000.00 | 8301 D 5000.00 | 4790 H 5000.00', 'concesión: ' || public.asiento(g, 'concession');
  perform erp.grant_collect(jsonb_build_object('grant_id', g, 'date', '2026-06-30'));
  assert public.asiento(g, 'collection') = '5720 D 20000.00 | 4708 H 20000.00', 'cobro';
  assert public.falla(format('select erp.grant_collect(%L)', jsonb_build_object('grant_id', g, 'date', '2026-07-01')), 'already collected');
  -- sin la amortización del año no se imputa
  x := erp.grant_year_end_preview(e, '2026-12-31');
  assert (x->>'depreciation_pending')::int = 1, 'falta amortizar: ' || x::text;
  assert public.falla(format('select erp.grant_year_end(%L, %L)', e, '2026-12-31'), 'not depreciated'), 'primero la amortización';
  perform erp.post_depreciation(e, '2026-12-31');
  x := erp.grant_year_end_preview(e, '2026-12-31')->'grants'->0;
  assert (x->>'imputation')::numeric = 2000 and (x->>'tax')::numeric = 500 and (x->>'pct')::numeric = 10, 'imputación: ' || x::text;
  perform erp.grant_year_end(e, '2026-12-31');
  assert public.asiento(g, 'imputation') = '8400 D 2000.00 | 7460 H 2000.00 | 4790 D 500.00 | 8301 H 500.00', 'imputación: ' || public.asiento(g, 'imputation');
  assert (erp.grant_year_end(e, '2026-12-31')->>'entries')::int = 0, 'el cierre no se repite';
  -- saldos al 31/12/2026 (antes de regularizar los grupos 8 y 9, que es de la 0065)
  assert public.saldo(e, '940', '2026-12-31') = 20000 and public.saldo(e, '840', '2026-12-31') = -2000
     and public.saldo(e, '8301', '2026-12-31') = -4500 and public.saldo(e, '479', '2026-12-31') = 4500 and public.saldo(e, '746', '2026-12-31') = 2000, 'saldos de 2026';
  -- en el balance, los grupos 8 y 9 ya son patrimonio neto (A-2 Subvenciones) antes de regularizarlos: 13.500
  assert (select sum(amount) from erp.fs_classified_accounts(e, 2026, 'balance', '2026-12-31') where line_code = 'PN.A2') = 13500, 'balance: A-2';
  -- grupos 9 − 8 = lo que irá a la 130: 13.500
  assert public.saldo(e, '9', '2026-12-31') + public.saldo(e, '8', '2026-12-31') = 13500, 'la futura 130';
  assert (select (y->>'pending')::numeric = 18000 and (y->>'deferred_tax')::numeric = 4500 from jsonb_array_elements(erp.grant_status(e)) y), 'estado';
  raise notice 'OK  · S1: concesión (4708 / 940 y 8301 / 479 5.000), cobro e imputación del 10 %% (840 / 746 2.000 y 479 / 8301 500)';
end $$;

-- ---------- S1b · Venta de la máquina al final de 2028 ----------
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 's1'); g uuid := (select c.e from public.ctx c where c.k = 's1g'); x jsonb;
begin
  perform erp.post_depreciation(e, '2027-12-31'); perform erp.grant_year_end(e, '2027-12-31');
  perform erp.post_depreciation(e, '2028-12-31'); perform erp.grant_year_end(e, '2028-12-31');
  assert (select (y->>'imputed')::numeric from jsonb_array_elements(erp.grant_status(e)) y where y->>'kind' = 'capital') = 6000, 'tres años imputados';
  x := erp.grant_impute_rest(jsonb_build_object('grant_id', g, 'date', '2028-12-31'));
  assert (x->>'amount')::numeric = 14000 and (x->>'tax')::numeric = 3500, 'lo pendiente: ' || x::text;
  assert public.asiento(g, 'disposal') = '8400 D 14000.00 | 7460 H 14000.00 | 4790 D 3500.00 | 8301 H 3500.00', 'baja';
  assert public.saldo(e, '479', '2028-12-31') = 0 and public.saldo(e, '9', '2028-12-31') + public.saldo(e, '8', '2028-12-31') = 0, 'todo a resultados';
  assert (select status from erp.grants where id = g) = 'imputed', 'imputada';
  assert public.falla(format('select erp.grant_impute_rest(%L)', jsonb_build_object('grant_id', g, 'date', '2028-12-31')), 'Only an active capital grant');
  raise notice 'OK  · S1b: al vender la máquina, los 14.000 pendientes a resultados y la 479 (3.500) a cero';
end $$;

-- ---------- S2 · Subvención a la explotación ----------
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 's1'); g uuid;
begin
  g := public.sub(e, '{"kind": "operating", "amount": 3000, "date": "2026-05-15", "description": "Curso de formación"}');
  assert public.asiento(g, 'concession') = '4708 D 3000.00 | 7400 H 3000.00', 'explotación: ' || public.asiento(g, 'concession');
  -- su 4708 es otra subcuenta (47089…): en el estado de flujos de efectivo el cobro es de explotación, no de financiación
  assert (select g2.account_no from erp.grants x join erp.gl_accounts g2 on g2.id = x.receivable_account_id where x.id = g) like '47089%', 'subcuenta de explotación';
  assert (select string_agg((select m.direct_line || '/' || m.home_line from erp.cf_mapping m where n like m.prefix || '%' order by length(m.prefix) desc limit 1), ' ' order by o)
          from unnest(array['47089001', '47080001', '94000001', '84000001', '83010001']) with ordinality u(n, o)) = 'DA4/IA3b DC1/IC1 DC1/IC1 DC1/IC1 DA6/IA4d', 'flujos de efectivo';
  assert not exists (select 1 from jsonb_array_elements(erp.grant_year_end_preview(e, '2026-12-31')->'grants') y where (y->>'grant_id')::uuid = g), 'no se imputa';
  raise notice 'OK  · S2: a la explotación, 4708 / 740 directamente a resultados';
end $$;

-- ---------- S3 · Reintegrable que deja de serlo ----------
do $$
declare e uuid := public.empresa('Reintegrable SL'); a uuid; g uuid; x jsonb;
begin
  insert into public.ctx values ('s3', e);
  perform erp.create_posting_account(e, '21300001', 'Maquinaria');
  a := public.activo(e, 30000, 60, '2027-04-01');
  g := public.sub(e, jsonb_build_object('amount', 10000, 'date', '2026-09-01', 'asset_id', a, 'refundable', true, 'condition_due', '2027-03-31', 'collected', true));
  insert into public.ctx values ('s3g', g);
  assert public.asiento(g, 'concession') = '5720 D 10000.00 | 5220 H 10000.00', 'cobrada y reintegrable: ' || public.asiento(g, 'concession');
  x := erp.grant_year_end_preview(e, '2026-12-31')->'grants'->0;
  assert not (x->>'unconditional')::boolean and (x->>'imputation')::numeric = 0, 'reintegrable: no se imputa';
  assert public.saldo(e, '9', '2026-12-31') = 0 and public.saldo(e, '522', '2026-12-31') = 10000, 'balance de 2026: una deuda';
  assert public.falla(format('select erp.grant_unconditional(%L)', jsonb_build_object('grant_id', g, 'date', '2026-08-31')), 'earlier than the last posting');
  perform erp.grant_unconditional(jsonb_build_object('grant_id', g, 'date', '2027-03-31'));
  assert public.asiento(g, 'unconditional') = '5220 D 10000.00 | 9400 H 10000.00 | 8301 D 2500.00 | 4790 H 2500.00', 'deja de ser reintegrable: ' || public.asiento(g, 'unconditional');
  perform erp.post_depreciation(e, '2027-12-31');
  x := erp.grant_year_end_preview(e, '2027-12-31')->'grants'->0;
  assert (x->>'imputation')::numeric = 1500 and (x->>'tax')::numeric = 375 and (x->>'pct')::numeric = 15, 'imputación de 2027: ' || x::text;
  perform erp.grant_year_end(e, '2027-12-31');
  -- con la condición a más de 12 meses, a largo plazo (172)
  g := public.sub(e, jsonb_build_object('amount', 1000, 'date', '2026-10-01', 'asset_id', a, 'refundable', true, 'condition_due', '2028-06-30'));
  assert public.asiento(g, 'concession') = '4708 D 1000.00 | 1720 H 1000.00', 'a largo: ' || public.asiento(g, 'concession');
  raise notice 'OK  · S3: reintegrable (572 / 522), deja de serlo (522 / 940 y 8301 / 479 2.500) e imputación del 15 %% (1.500 y 375)';
end $$;

-- ---------- Datos no válidos ----------
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 's3'); a uuid := (select asset_id from erp.grants where id = (select c.e from public.ctx c where c.k = 's3g'));
begin
  assert public.falla(format('select public.sub(%L, %L)', e, jsonb_build_object('amount', 100, 'date', '2026-05-01')), 'Choose the fixed asset');
  assert public.falla(format('select public.sub(%L, %L)', e, jsonb_build_object('amount', 50000, 'date', '2026-05-01', 'asset_id', a)), 'cannot exceed the cost');
  assert public.falla(format('select public.sub(%L, %L)', e, jsonb_build_object('amount', 100, 'date', '2026-05-01', 'asset_id', a, 'refundable', true)), 'condition falls due');
  assert public.falla(format('select public.sub(%L, %L)', e, jsonb_build_object('amount', 0, 'date', '2026-05-01', 'asset_id', a)), 'must be positive');
  assert public.falla(format('select public.sub(%L, %L)', e, jsonb_build_object('amount', 100, 'date', '2031-05-01', 'asset_id', a)), 'No fiscal year');
  assert public.falla(format('select erp.grant_unconditional(%L)', jsonb_build_object('grant_id', (select id from erp.grants where company_id = (select c.e from public.ctx c where c.k = 's1') and kind = 'operating'), 'date', '2026-12-31')), 'not refundable');
  raise notice 'OK  · datos no válidos: sin activo, más que su coste, reintegrable sin fecha, importe cero, sin ejercicio';
end $$;

-- ---------- Deshacer, módulo propio e invariantes ----------
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 's3'); g uuid := (select c.e from public.ctx c where c.k = 's3g'); x uuid; n int;
begin
  assert erp.grant_cancel(g)->>'kind' = 'imputation', 'primero la imputación';
  x := (select entry_id from erp.grant_events where grant_id = g and kind = 'unconditional' and status = 'posted');
  assert public.falla(format('select erp.reverse_entry(%L, %L, %L)', x, '2027-12-31', 'x'), 'belongs to a grant'), 'no se anula desde el diario';
  assert (select distinct source from erp.v_general_journal where entry_id = x) = 'grant', 'origen en el diario';
  assert (select count(*) from erp.audit_lines(e, 2027) where entry_id = x and source = 'grant') > 0, 'origen en el auditor';
  assert erp.grant_cancel(g)->>'kind' = 'unconditional', 'luego deja de ser no reintegrable';
  assert public.saldo(e, '522', '2027-12-31') = 10000 and public.saldo(e, '9', '2027-12-31') = 0, 'vuelve a ser una deuda';
  assert erp.grant_cancel(g)->>'kind' = 'concession', 'y la concesión';
  assert (select status from erp.grants where id = g) = 'cancelled' and public.saldo(e, '522', '2027-12-31') = 0, 'anulada';
  assert public.falla(format('select erp.grant_cancel(%L)', g), 'already cancelled');
  execute 'set constraints all immediate'; execute 'set constraints all deferred';
  select count(*) into n from erp.integrity_checks((select c.e from public.ctx c where c.k = 's1'), 2026) where status = 'fail';
  assert n = 0, (select string_agg(code, ', ') from erp.integrity_checks((select c.e from public.ctx c where c.k = 's1'), 2026) where status = 'fail');
  raise notice 'OK  · deshacer del último al primero; módulo propio en el diario y el auditor; invariantes en verde';
end $$;

reset role;
do $$
begin
  assert not erp.entry_is_manual((select entry_id from erp.grant_events order by seq limit 1)), 'no es un asiento manual';
end $$;
set role authenticated;

-- ---------- Seguridad ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 's1'); g uuid := (select c.e from public.ctx c where c.k = 's1g');
begin
  assert (select count(*) from erp.grants) = 0 and (select count(*) from erp.grant_events) = 0, 'otro usuario no ve las subvenciones';
  assert public.falla(format('select erp.grant_status(%L)', e), 'No permission');
  assert public.falla(format('select erp.grant_year_end(%L, %L)', e, '2026-12-31'), 'No permission');
  assert public.falla(format('select erp.grant_cancel(%L)', g), 'No permission');
  assert public.falla($q$select erp.grant_position(gen_random_uuid())$q$, 'permission denied'), 'las ayudas no son públicas';
  raise notice 'OK  · otro usuario no ve ni registra subvenciones de una empresa ajena';
end $$;

\echo '✔ FASE 59 OK · Subvenciones de capital y a la explotación, reintegrables, imputación y baja (supuestos S1 a S3)'
