-- =====================================================================
-- PRUEBAS FASE 55 · Operaciones societarias (migración 0060 · v0.42.0)
-- ---------------------------------------------------------------------
-- Supuestos de referencia calculados a mano desde la LSC y el PGC antes de programar (docs del proyecto:
-- supuestos-v0.42.0.md). La reserva legal sobre el beneficio aunque haya pérdidas: PENDIENTE DE VALIDAR POR DIOSVELY.
--   S1  SA: capital 60.000, 25 % desembolsado → 190/194 · 572 15.000 + 1030 45.000 / 190 · 194/100; gastos de
--       constitución 1.200 contra la 113; se exige la mitad (22.500) y se cobra → patrimonio neto 36.300
--   S2  SA: ampliación de 100.000 nominal con 20.000 de prima → 190 120.000 / 194 100.000 + 110 20.000
--   S3  SL: capital 30.000, reserva legal 4.000, beneficio 50.000, dividendo 30.000 → 112 2.000 (hasta el 20 %),
--       113 18.000, 526 30.000; pago: 4751 5.700 (19 %) y banco 24.300 · patrimonio neto 84.000 → 54.000
--   S3b SL de 1.000 €: beneficio 8.000 → reserva legal 1.600 (20 %); al año siguiente, 400 (hasta 3.000)
--   S4  SL: a 30/09, resultado 40.000 → límite 40.000 − 10.000 − 3.000 = 27.000; a cuenta 20.000 (pago 3.800 /
--       16.200); junta: beneficio 45.000, dividendo 30.000 → 112 4.500 · 557 20.000 · 526 10.000 · 113 10.500
--   S5  SL: pérdida 20.000 → 121; al año siguiente beneficio 50.000 → 121 20.000 · 112 5.000 · 113 25.000;
--       dividendo máximo 25.000
--   S6  SL: pérdida 18.000 → reducción de capital 100 / 121 (art. 320): capital 12.000
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
create or replace function public.empresa(nombre text, forma text default 'sl') returns uuid language plpgsql as $$
declare e uuid; c text;
begin
  insert into erp.companies (name, industry, tax_territory, created_by) values (nombre, 'services', 'mainland', auth.uid()) returning id into e;
  perform erp.create_fiscal_year(e, 2026); perform erp.create_fiscal_year(e, 2027); perform erp.create_fiscal_year(e, 2028);
  perform erp.setup_taxes(e);
  perform erp.set_legal_form(e, forma);
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
create or replace function public.asiento(e uuid, p_code text, n int) returns text language sql as $$
  select string_agg(g.account_no || case when l.debit <> 0 then ' D ' || l.debit else ' H ' || l.credit end, ' | ' order by l.line_no)
  from erp.journal_lines l join erp.gl_accounts g on g.id = l.gl_account_id
  where l.entry_id = (select o.entry_ids[n] from erp.equity_operations o where o.company_id = e and o.code = p_code);
$$;
create or replace function public.st(e uuid, d date, k text) returns numeric language sql as $$ select (erp.equity_status(e, d)->>k)::numeric $$;
create or replace function public.op(e uuid) returns uuid language sql as $$
  select id from erp.equity_operations where company_id = e and status = 'posted' order by code desc limit 1 $$;
grant execute on function public.falla(text, text), public.empresa(text, text), public.manual(uuid, date, jsonb), public.asiento(uuid, text, int),
  public.st(uuid, date, text), public.op(uuid) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

-- ---------- S1 · Constitución de una SA con desembolso pendiente ----------
do $$
declare e uuid := public.empresa('Anónima SA', 'sa'); s uuid := public.empresa('Limitada SL'); g jsonb;
begin
  insert into public.ctx values ('sa', e);
  assert public.falla(format($q$select erp.equity_incorporation('{"company_id": "%s", "date": "2026-01-15", "capital": 50000, "paid_pct": 25}')$q$, e), 'at least 60,000'), 'SA: 60.000 mínimo';
  assert public.falla(format($q$select erp.equity_incorporation('{"company_id": "%s", "date": "2026-01-15", "capital": 60000, "paid_pct": 20}')$q$, e), 'at least 25'), 'SA: 25 % mínimo';
  assert public.falla(format($q$select erp.equity_incorporation('{"company_id": "%s", "date": "2026-01-15", "capital": 3000, "paid_pct": 50}')$q$, s), 'fully paid'), 'SL: todo desembolsado';
  g := erp.equity_incorporation(jsonb_build_object('company_id', e, 'date', '2026-01-15', 'capital', 60000, 'paid_pct', 25));
  assert (g->>'paid')::numeric = 15000 and (g->>'uncalled')::numeric = 45000 and jsonb_array_length(g->'entry_nos') = 3, g::text;
  assert public.asiento(e, 'SOC-0001', 1) = '19000001 D 60000.00 | 19400001 H 60000.00', public.asiento(e, 'SOC-0001', 1);
  assert public.asiento(e, 'SOC-0001', 2) = '57200001 D 15000.00 | 10300001 D 45000.00 | 19000001 H 60000.00', public.asiento(e, 'SOC-0001', 2);
  assert public.asiento(e, 'SOC-0001', 3) = '19400001 D 60000.00 | 10000001 H 60000.00', public.asiento(e, 'SOC-0001', 3);
  assert public.falla(format($q$select erp.equity_incorporation('{"company_id": "%s", "date": "2026-02-01", "capital": 60000}')$q$, e), 'already has share capital');
  assert public.falla(format('select erp.set_legal_form(%L, %L)', e, 'sl'), 'already has equity operations'), 'la forma no cambia con operaciones';
  -- gastos de constitución contra reservas (NRV 9.ª): de momento, un asiento (con su factura llegará en la integración)
  perform public.manual(e, '2026-01-20', '[["11300001", 1200, 0], ["47200021", 252, 0], ["41000001", 0, 1452]]');
  -- dividendo pasivo: no más de lo pendiente; la mitad, exigida y cobrada
  assert public.falla(format($q$select erp.equity_call('{"company_id": "%s", "date": "2026-06-01", "amount": 50000}')$q$, e), 'between 0 and the uncalled');
  g := erp.equity_call(jsonb_build_object('company_id', e, 'date', '2026-06-01', 'amount', 22500, 'paid', true));
  assert public.asiento(e, 'SOC-0002', 1) = '55800001 D 22500.00 | 10300001 H 22500.00', public.asiento(e, 'SOC-0002', 1);
  assert public.asiento(e, 'SOC-0002', 2) = '57200001 D 22500.00 | 55800001 H 22500.00', public.asiento(e, 'SOC-0002', 2);
  assert public.st(e, '2026-06-30', 'uncalled') = 22500 and public.st(e, '2026-06-30', 'called_unpaid') = 0, erp.equity_status(e, '2026-06-30')::text;
  assert public.st(e, '2026-06-30', 'net_worth') = 36300, 'patrimonio neto: ' || public.st(e, '2026-06-30', 'net_worth');
  raise notice 'OK  · S1: constitución de la SA (25 %%), gastos contra la 113, dividendo pasivo cobrado → patrimonio neto 36.300';
end $$;

-- ---------- S2 · Ampliación de capital con prima y con cargo a reservas ----------
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 'sa'); g jsonb;
begin
  g := erp.equity_capital_increase(jsonb_build_object('company_id', e, 'date', '2026-09-01', 'nominal', 100000, 'premium', 20000));
  assert public.asiento(e, 'SOC-0003', 1) = '19000001 D 120000.00 | 19400001 H 100000.00 | 11000001 H 20000.00', public.asiento(e, 'SOC-0003', 1);
  assert public.asiento(e, 'SOC-0003', 2) = '57200001 D 120000.00 | 19000001 H 120000.00', public.asiento(e, 'SOC-0003', 2);
  assert public.asiento(e, 'SOC-0003', 3) = '19400001 D 100000.00 | 10000001 H 100000.00', public.asiento(e, 'SOC-0003', 3);
  assert public.st(e, '2026-09-30', 'capital') = 160000 and public.st(e, '2026-09-30', 'premium') = 20000;
  assert public.falla(format($q$select erp.equity_reserves_to_capital('{"company_id": "%s", "date": "2026-10-01", "amount": 30000}')$q$, e), 'Not enough voluntary reserves'),
         'con la 113 en negativo (los gastos) no hay reservas que pasar a capital';
  g := erp.equity_reserves_to_capital(jsonb_build_object('company_id', e, 'date', '2026-10-01', 'amount', 10000, 'source', '110'));
  assert public.asiento(e, 'SOC-0004', 1) = '11000001 D 10000.00 | 10000001 H 10000.00', public.asiento(e, 'SOC-0004', 1);
  assert public.st(e, '2026-10-31', 'capital') = 170000 and public.st(e, '2026-10-31', 'premium') = 10000;
  raise notice 'OK  · S2: ampliación de 100.000 con 20.000 de prima; 10.000 de la prima pasan a capital';
end $$;

-- ---------- S3 · Reparto del resultado de una SL ----------
do $$
declare e uuid := public.empresa('Reparto SL'); g jsonb;
begin
  insert into public.ctx values ('reparto', e);
  perform erp.equity_incorporation(jsonb_build_object('company_id', e, 'date', '2026-01-02', 'capital', 30000));
  perform public.manual(e, '2026-01-03', '[["57200001", 4000, 0], ["11200001", 0, 4000]]');   -- reserva legal de años anteriores
  perform public.manual(e, '2026-06-30', '[["57200001", 50000, 0], ["70500001", 0, 50000]]');
  perform erp.close_fiscal_year(e, 2026, true);
  assert public.st(e, '2027-05-20', 'result_to_distribute') = 50000, erp.equity_status(e, '2027-05-20')::text;
  g := erp.equity_distribution_preview(jsonb_build_object('company_id', e, 'date', '2027-05-20', 'dividend', 30000));
  assert (g->>'legal_reserve')::numeric = 2000 and (g->>'legal_reserve_min')::numeric = 2000 and (g->>'voluntary')::numeric = 18000
     and (g->>'net_worth_before')::numeric = 84000 and (g->>'net_worth_after')::numeric = 54000 and (g->>'ok')::boolean, g::text;
  assert not (erp.equity_distribution_preview(jsonb_build_object('company_id', e, 'date', '2027-05-20', 'dividend', 49000))->>'ok')::boolean, 'más de lo disponible';
  assert public.falla(format($q$select erp.equity_distribution('{"company_id": "%s", "date": "2027-05-20", "dividend": 30000, "legal_reserve": 1000}')$q$, e), 'legal_reserve_below_min');
  g := erp.equity_distribution(jsonb_build_object('company_id', e, 'date', '2027-05-20', 'dividend', 30000));
  assert public.asiento(e, (g->>'code'), 1) = '12900000 D 50000.00 | 11200001 H 2000.00 | 52600001 H 30000.00 | 11300001 H 18000.00', public.asiento(e, (g->>'code'), 1);
  assert public.st(e, '2027-05-31', 'result_to_distribute') = 0 and public.st(e, '2027-05-31', 'legal_reserve') = 6000;
  -- pago con retención (y sin ella, con su motivo)
  assert public.falla(format($q$select erp.equity_dividend_payment('{"company_id": "%s", "date": "2027-06-01", "withholding_pct": 0}')$q$, e), 'say why');
  assert public.falla(format($q$select erp.equity_dividend_payment('{"company_id": "%s", "date": "2027-06-01", "withholding_pct": 15}')$q$, e), '19 %');
  g := erp.equity_dividend_payment(jsonb_build_object('company_id', e, 'date', '2027-06-01', 'amount', 20000));
  assert public.asiento(e, (g->>'code'), 1) = '52600001 D 20000.00 | 47512001 H 3800.00 | 57200001 H 16200.00', public.asiento(e, (g->>'code'), 1);
  g := erp.equity_dividend_payment(jsonb_build_object('company_id', e, 'date', '2027-06-02', 'no_withholding_reason', 'Socio sociedad con exención (art. 21 LIS)'));
  assert (g->>'gross')::numeric = 10000 and (g->>'withholding')::numeric = 0, g::text;
  assert public.asiento(e, (g->>'code'), 1) = '52600001 D 10000.00 | 57200001 H 10000.00', public.asiento(e, (g->>'code'), 1);
  assert public.st(e, '2027-06-30', 'dividend_payable') = 0;
  raise notice 'OK  · S3: reserva legal 2.000 (hasta el 20 %% del capital), 113 18.000, dividendo 30.000; pago con el 19 %% y sin retención con motivo';
end $$;

-- ---------- S3b · SL de capital inferior a 3.000 € (art. 4.2 LSC) ----------
do $$
declare e uuid := public.empresa('Un euro SL'); g jsonb;
begin
  perform erp.equity_incorporation(jsonb_build_object('company_id', e, 'date', '2026-01-02', 'capital', 1000));
  perform public.manual(e, '2026-06-30', '[["57200001", 8000, 0], ["70500001", 0, 8000]]');
  perform erp.close_fiscal_year(e, 2026, true);
  assert (erp.equity_status(e, '2027-01-01')->>'low_capital_sl')::boolean and public.st(e, '2027-01-01', 'legal_reserve_cap') = 2000;
  g := erp.equity_distribution(jsonb_build_object('company_id', e, 'date', '2027-04-01'));
  assert (g->>'legal_reserve')::numeric = 1600 and (g->>'voluntary')::numeric = 6400, g::text;
  perform public.manual(e, '2027-06-30', '[["57200001", 8000, 0], ["70500001", 0, 8000]]');
  perform erp.close_fiscal_year(e, 2027, true);
  assert (erp.equity_distribution_preview(jsonb_build_object('company_id', e, 'date', '2028-04-01'))->>'legal_reserve')::numeric = 400, 'al año siguiente, hasta 3.000';
  raise notice 'OK  · S3b: SL de 1.000 €: reserva legal del 20 %% (1.600) y al año siguiente lo que falta hasta 3.000 (400)';
end $$;

-- ---------- S4 · Dividendo a cuenta (art. 277 LSC) ----------
do $$
declare e uuid := public.empresa('A cuenta SL'); g jsonb;
begin
  perform erp.equity_incorporation(jsonb_build_object('company_id', e, 'date', '2026-01-02', 'capital', 30000));
  perform public.manual(e, '2026-08-31', '[["57200001", 40000, 0], ["70500001", 0, 40000]]');
  g := erp.equity_interim_preview(jsonb_build_object('company_id', e, 'date', '2026-09-30', 'amount', 20000));
  assert (g->>'result_since_close')::numeric = 40000 and (g->>'estimated_tax')::numeric = 10000 and (g->>'legal_reserve')::numeric = 3000
     and (g->>'max')::numeric = 27000 and (g->>'ok')::boolean, g::text;
  assert public.falla(format($q$select erp.equity_interim_dividend('{"company_id": "%s", "date": "2026-09-30", "amount": 28000}')$q$, e), 'interim_above_limit');
  g := erp.equity_interim_dividend(jsonb_build_object('company_id', e, 'date', '2026-09-30', 'amount', 20000));
  assert public.asiento(e, (g->>'code'), 1) = '55700001 D 20000.00 | 52600001 H 20000.00', public.asiento(e, (g->>'code'), 1);
  g := erp.equity_dividend_payment(jsonb_build_object('company_id', e, 'date', '2026-10-05'));
  assert public.asiento(e, (g->>'code'), 1) = '52600001 D 20000.00 | 47512001 H 3800.00 | 57200001 H 16200.00', public.asiento(e, (g->>'code'), 1);
  assert (erp.equity_interim_preview(jsonb_build_object('company_id', e, 'date', '2026-10-10', 'amount', 10000))->>'max')::numeric = 7000, 'lo ya repartido a cuenta cuenta';
  assert public.st(e, '2026-10-31', 'net_worth') = 30000 + 40000 - 20000, 'la 557 resta del patrimonio neto';
  perform public.manual(e, '2026-12-15', '[["57200001", 5000, 0], ["70500001", 0, 5000]]');
  perform erp.close_fiscal_year(e, 2026, true);
  assert public.falla(format($q$select erp.equity_distribution('{"company_id": "%s", "date": "2027-05-20", "dividend": 15000}')$q$, e), 'dividend_below_interim');
  g := erp.equity_distribution(jsonb_build_object('company_id', e, 'date', '2027-05-20', 'dividend', 30000));
  assert public.asiento(e, (g->>'code'), 1) = '12900000 D 45000.00 | 11200001 H 4500.00 | 55700001 H 20000.00 | 52600001 H 10000.00 | 11300001 H 10500.00',
         public.asiento(e, (g->>'code'), 1);
  assert public.st(e, '2027-05-31', 'interim_dividend') = 0 and public.st(e, '2027-05-31', 'dividend_payable') = 10000;
  raise notice 'OK  · S4: dividendo a cuenta 20.000 (límite 27.000); junta: 112 4.500, 557 20.000, 526 10.000, 113 10.500';
end $$;

-- ---------- S5 · Pérdidas y su compensación ----------
do $$
declare e uuid := public.empresa('Pérdidas SL'); g jsonb;
begin
  perform erp.equity_incorporation(jsonb_build_object('company_id', e, 'date', '2026-01-02', 'capital', 30000));
  perform public.manual(e, '2026-06-30', '[["62900001", 20000, 0], ["57200001", 0, 20000]]');
  perform erp.close_fiscal_year(e, 2026, true);
  assert public.falla(format($q$select erp.equity_distribution('{"company_id": "%s", "date": "2027-05-20", "dividend": 1000}')$q$, e), 'dividend_with_loss');
  g := erp.equity_distribution(jsonb_build_object('company_id', e, 'date', '2027-05-20'));
  assert public.asiento(e, (g->>'code'), 1) = '12100001 D 20000.00 | 12900000 H 20000.00', public.asiento(e, (g->>'code'), 1);
  assert public.st(e, '2027-05-31', 'prior_losses') = 20000 and public.st(e, '2027-05-31', 'net_worth') = 10000;
  perform public.manual(e, '2027-06-30', '[["57200001", 50000, 0], ["70500001", 0, 50000]]');
  perform erp.close_fiscal_year(e, 2027, true);
  g := erp.equity_distribution_preview(jsonb_build_object('company_id', e, 'date', '2028-05-20', 'dividend', 25000));
  assert (g->>'offset_losses')::numeric = 20000 and (g->>'legal_reserve')::numeric = 5000 and (g->>'available')::numeric = 25000
     and (g->>'net_worth_after')::numeric = 35000 and (g->>'ok')::boolean, 'dividendo máximo 25.000: ' || g::text;
  assert not (erp.equity_distribution_preview(jsonb_build_object('company_id', e, 'date', '2028-05-20', 'dividend', 25000.01))->>'ok')::boolean;
  assert not (erp.equity_distribution_preview(jsonb_build_object('company_id', e, 'date', '2028-05-20', 'dividend', 1000, 'offset_losses', 10000))->>'ok')::boolean,
         'sin compensar todas las pérdidas no hay dividendo (art. 273.2)';
  g := erp.equity_distribution(jsonb_build_object('company_id', e, 'date', '2028-05-20'));
  assert public.asiento(e, (g->>'code'), 1) = '12900000 D 50000.00 | 12100001 H 20000.00 | 11200001 H 5000.00 | 11300001 H 25000.00', public.asiento(e, (g->>'code'), 1);
  assert public.st(e, '2028-05-31', 'prior_losses') = 0 and public.st(e, '2028-05-31', 'net_worth') = 60000;
  raise notice 'OK  · S5: pérdida a la 121; al año siguiente compensa 20.000, reserva legal 5.000, 113 25.000 (dividendo máximo 25.000)';
end $$;

-- ---------- S6 · Pérdidas: con reservas y reduciendo el capital ----------
do $$
declare e uuid := public.empresa('Reducción SL'); r uuid := (select c.e from public.ctx c where c.k = 'reparto'); g jsonb;
begin
  perform erp.equity_incorporation(jsonb_build_object('company_id', e, 'date', '2026-01-02', 'capital', 30000));
  perform public.manual(e, '2026-06-30', '[["62900001", 18000, 0], ["57200001", 0, 18000]]');
  perform erp.close_fiscal_year(e, 2026, true);
  perform erp.equity_distribution(jsonb_build_object('company_id', e, 'date', '2027-05-20'));
  assert public.falla(format($q$select erp.equity_loss_offset('{"company_id": "%s", "date": "2027-06-01", "amount": 18000}')$q$, e), 'Not enough voluntary reserves');
  assert public.falla(format($q$select erp.equity_capital_reduction('{"company_id": "%s", "date": "2027-06-01", "amount": 20000}')$q$, e), 'between 0 and the pending losses');
  g := erp.equity_capital_reduction(jsonb_build_object('company_id', e, 'date', '2027-06-01', 'amount', 18000));
  assert public.asiento(e, (g->>'code'), 1) = '10000001 D 18000.00 | 12100001 H 18000.00', public.asiento(e, (g->>'code'), 1);
  assert public.st(e, '2027-06-30', 'capital') = 12000 and public.st(e, '2027-06-30', 'prior_losses') = 0;
  -- con reservas voluntarias, primero ellas (art. 322): la empresa del S3 tiene 18.000 en la 113
  perform public.manual(r, '2027-07-01', '[["12100001", 5000, 0], ["57200001", 0, 5000]]');   -- (pérdidas de otro origen, para el supuesto)
  assert public.falla(format($q$select erp.equity_capital_reduction('{"company_id": "%s", "date": "2027-07-02", "amount": 5000}')$q$, r), 'voluntary reserves first');
  g := erp.equity_loss_offset(jsonb_build_object('company_id', r, 'date', '2027-07-02', 'amount', 5000));
  assert public.asiento(r, (g->>'code'), 1) = '11300001 D 5000.00 | 12100001 H 5000.00', public.asiento(r, (g->>'code'), 1);
  raise notice 'OK  · S6: reducción de capital por pérdidas (capital 12.000); con reservas voluntarias, primero ellas';
end $$;

-- ---------- Deshacer, módulo propio e invariantes ----------
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 'sa'); r uuid := (select c.e from public.ctx c where c.k = 'reparto'); x uuid; n int;
begin
  -- de la última a la primera
  assert public.falla(format('select erp.equity_cancel(%L)', (select id from erp.equity_operations where company_id = e and code = 'SOC-0001')), 'later equity operations');
  perform erp.equity_cancel(public.op(e));   -- la ampliación con cargo a la prima
  assert public.st(e, '2026-10-31', 'capital') = 160000 and public.st(e, '2026-10-31', 'premium') = 20000, 'deshecha: ' || erp.equity_status(e, '2026-10-31')::text;
  assert public.falla(format('select erp.equity_cancel(%L)', (select id from erp.equity_operations where company_id = e and code = 'SOC-0004')), 'already cancelled'), 'ya deshecha';
  -- los asientos no se anulan desde el diario, salen como «equity» y no son manuales
  x := (select entry_ids[1] from erp.equity_operations where company_id = e and code = 'SOC-0003');
  assert public.falla(format('select erp.reverse_entry(%L, %L, %L)', x, '2026-12-31', 'x'), 'equity operation'), 'no se anula desde el diario';
  assert (select distinct source from erp.v_general_journal where entry_id = x) = 'equity', 'origen en el diario';
  -- el reparto deshecho devuelve el resultado a la 129 (y antes hay que deshacer el pago y la compensación)
  perform erp.equity_cancel(public.op(r)); perform erp.equity_cancel(public.op(r)); perform erp.equity_cancel(public.op(r));
  assert public.st(r, '2027-07-31', 'dividend_payable') = 30000, 'pagos deshechos: ' || erp.equity_status(r, '2027-07-31')::text;
  perform erp.equity_cancel(public.op(r));
  assert public.st(r, '2027-07-31', 'result_to_distribute') = 50000 and public.st(r, '2027-07-31', 'legal_reserve') = 4000, 'reparto deshecho: ' || erp.equity_status(r, '2027-07-31')::text;
  execute 'set constraints all immediate'; execute 'set constraints all deferred';
  select count(*) into n from erp.integrity_checks(r, 2027) where status = 'fail';
  assert n = 0, (select string_agg(code, ', ') from erp.integrity_checks(r, 2027) where status = 'fail');
  raise notice 'OK  · deshacer de la última a la primera; módulo propio en el diario; invariantes en verde';
end $$;

reset role;
do $$
begin
  assert not erp.entry_is_manual((select entry_ids[1] from erp.equity_operations order by created_at limit 1)), 'no es un asiento manual';
end $$;
set role authenticated;

-- ---------- Seguridad ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 'sa');
begin
  assert (select count(*) from erp.equity_operations) = 0, 'otro usuario no ve las operaciones';
  assert public.falla(format('select erp.equity_status(%L, %L)', e, '2026-12-31'), 'No permission');
  assert public.falla(format($q$select erp.equity_call('{"company_id": "%s", "date": "2026-11-01", "amount": 100}')$q$, e), 'No permission');
  assert public.falla(format('select erp.set_legal_form(%L, %L)', e, 'sl'), 'Only the company admin');
  raise notice 'OK  · otro usuario no ve ni registra operaciones societarias de una empresa ajena';
end $$;

\echo '✔ FASE 55 OK · Operaciones societarias: constitución, ampliación, reparto, dividendos y pérdidas (supuestos S1 a S6)'
