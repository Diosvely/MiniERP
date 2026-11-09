-- =====================================================================
-- PRUEBAS FASE 52 · Impuesto sobre Sociedades (I): cálculo, ajustes y régimen (migración 0057 · v0.41.0)
-- ---------------------------------------------------------------------
-- SUPUESTO DE REFERENCIA 1 (calculado a mano desde la Ley 27/2014; tipos de 2026 pendientes de validar en el BOE):
--   Sociedad de servicios, primer ejercicio (2026). Operaciones:
--     ingresos por servicios (705) 300.000 · alquiler (621) 60.000 · otros servicios (629) 40.000
--     multa de tráfico (678) 1.000 · provisión por un litigio (678 / 142) 12.000
--     máquina de 20.000 desde el 01/01, vida útil 4 años (25 %): amortización contable 5.000
--     pagos fraccionados del IS (473) 10.000
--   Resultado antes de impuestos = 300.000 − 60.000 − 40.000 − 1.000 − 12.000 − 5.000 = 182.000
--   Ajustes:
--     + 1.000 permanente: multa (art. 15.c LIS: no deducible)                                 (manual)
--     + 2.600 temporaria: amortización 5.000 − máximo fiscal 20.000 × 12 % = 2.400 (art. 12.1.a, tabla: maquinaria)
--       la provisión del litigio se propone sin incluir: deducible si nace de una obligación legal (art. 14.1)
--   Base imponible previa = 182.000 + 1.000 + 2.600 = 185.600 · sin bases negativas → base imponible 185.600
--   Microempresa (cifra de negocios 300.000 < 1 M, DT 44.ª): 50.000 × 19 % + 135.600 × 21 % = 9.500 + 28.476 = 37.976
--   Cuota diferencial = 37.976 − 10.000 = 27.976 a ingresar (4752)
--   Impuesto diferido: 2.600 × 21 % = 546 de activo (4740) → 6301 = −546
--   Gasto por impuesto = 37.976 − 546 = 37.430 = (182.000 + 1.000) con la escala: las diferencias temporarias no cambian el
--   gasto total, solo cuándo se paga (NRV 13.ª). Resultado después de impuestos = 182.000 − 37.430 = 144.570.
--   Régimen general (25 %): cuota 46.400; diferido −650; gasto 45.750 = 183.000 × 25 %.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local'),
                                          ('00000000-0000-0000-0000-0000000000b2', 'otro@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);

create or replace function public.falla(sql text, texto text) returns boolean language plpgsql as $$
begin
  execute sql;
  return false;
exception when others then
  if sqlerrm ilike '%' || texto || '%' then return true; end if;
  raise notice 'error inesperado: %', sqlerrm;
  return false;
end $$;
create or replace function public.manual(e uuid, d date, l jsonb) returns void language plpgsql as $$
declare a uuid;
begin
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and year = extract(year from d)), d, 'Supuesto') returning id into a;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit)
  select a, e, x.ord, (select id from erp.gl_accounts where company_id = e and account_no = x.v->>0), (x.v->>1)::numeric, (x.v->>2)::numeric
  from jsonb_array_elements(l) with ordinality as x(v, ord);
  perform erp.post_entry(a);
end $$;
grant execute on function public.falla(text, text), public.manual(uuid, date, jsonb) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

create temp table ctx (e uuid);
grant all on ctx to authenticated;

do $$
declare e uuid; c text; r record; maq uuid; v_ret uuid; g jsonb; adj uuid;
begin
  insert into erp.companies (name, industry, tax_territory, created_by) values ('Supuesto IS SL', 'services', 'mainland', auth.uid())
  returning id into e;
  insert into ctx values (e);
  perform erp.create_fiscal_year(e, 2026);
  perform erp.setup_taxes(e);
  foreach c in array array['57200001:Banco', '70500001:Prestación de servicios', '62100001:Alquiler', '62900001:Otros servicios',
                           '67800001:Gastos excepcionales', '47300001:HP retenciones y pagos a cuenta', '21300001:Maquinaria'] loop
    if not exists (select 1 from erp.gl_accounts where company_id = e and account_no = split_part(c, ':', 1)) then
      perform erp.create_posting_account(e, split_part(c, ':', 1), split_part(c, ':', 2));
    end if;
  end loop;
  perform public.manual(e, '2026-06-30', '[["57200001", 300000, 0], ["70500001", 0, 300000]]');
  perform public.manual(e, '2026-06-30', '[["62100001", 60000, 0], ["62900001", 40000, 0], ["57200001", 0, 100000]]');
  perform public.manual(e, '2026-09-10', '[["67800001", 1000, 0], ["57200001", 0, 1000]]');
  perform public.manual(e, '2026-10-20', '[["47300001", 10000, 0], ["57200001", 0, 10000]]');
  perform erp.create_provision(jsonb_build_object('company_id', e, 'kind', 'liabilities', 'term', 'long',
    'description', 'Demanda de un cliente', 'amount', 12000, 'provision_date', '2026-12-31', 'expense_account_no', '67800001'));
  select asset_id into maq from erp.create_fixed_asset(jsonb_build_object('company_id', e, 'name', 'Máquina',
    'asset_account_no', '21300001', 'cost', 20000, 'start_date', '2026-01-01', 'useful_life_months', 48, 'class_code', 'MAQUINARIA'));
  perform erp.post_depreciation(e, '2026-12-31');

  -- ---------- 1. Piezas: resultado, cifra de negocios y régimen sugerido ----------
  assert erp.pre_tax_result(e, (select id from erp.fiscal_years where company_id = e and year = 2026)) = 182000, 'resultado antes de impuestos';
  g := erp.corporate_tax_regime_hint(e, 2026);
  assert (g->>'turnover')::numeric = 300000 and g->>'suggested' = 'micro' and (g->>'is_erd')::boolean and (g->>'basis_year')::int = 2026, g::text;
  assert (erp.corporate_tax_quota(2026, 'micro', 185600)->>'quota')::numeric = 37976, 'escala de la microempresa';
  assert (erp.corporate_tax_quota(2026, 'micro', 40000)->>'quota')::numeric = 7600
     and (erp.corporate_tax_quota(2026, 'micro', 40000)->>'marginal_rate')::numeric = 19, 'base por debajo de 50.000: todo al 19 %';
  assert (erp.corporate_tax_quota(2026, 'erd', 100000)->>'quota')::numeric = 23000 and (erp.corporate_tax_quota(2026, 'new_entity', 100000)->>'quota')::numeric = 15000;
  assert public.falla($q$select erp.corporate_tax_quota(2024, 'general', 1)$q$, 'No corporate tax rates'), 'sin tipos para el año: avisa';
  -- v0.60.2 · AF-02 (regresión, regla A1): la microempresa de 2025 y desde 2027 (art. 29.1 y DT 44.ª LIS, Ley 7/2024).
  -- Antes de la 0091, 2027 daba 20.000 (los tipos de 2026) y 2025 daba error
  assert (erp.corporate_tax_quota(2027, 'micro', 100000)->>'quota')::numeric = 18500
     and (erp.corporate_tax_quota(2027, 'micro', 100000)->>'marginal_rate')::numeric = 20, 'desde 2027: 17 % × 50.000 + 20 % × 50.000';
  assert (erp.corporate_tax_quota(2028, 'micro', 40000)->>'quota')::numeric = 6800, '2028: todo al 17 %';
  assert (erp.corporate_tax_quota(2025, 'micro', 100000)->>'quota')::numeric = 21500, '2025: 21 % × 50.000 + 22 % × 50.000';
  -- AF-03: el tramo por días si el período impositivo dura menos de un año (50.000 × 184 / 365 = 25.205,48)
  assert (erp.corporate_tax_quota(2026, 'micro', 40000, 184)->>'quota')::numeric = 7895.89, '184 días: 25.205,48 × 19 % + 14.794,52 × 21 %';
  assert (erp.corporate_tax_quota(2026, 'micro', 40000, 365)->>'quota')::numeric = 7600
     and (erp.corporate_tax_quota(2026, 'micro', 40000, 366)->>'quota')::numeric = 7600, 'un año entero (también bisiesto): sin reparto';
  assert (erp.corporate_tax_quota(2026, 'erd', 100000, 184)->>'quota')::numeric = 23000, 'sin tramos, los días no cambian nada';
  raise notice 'OK  · resultado 182.000, cifra de negocios 300.000 → microempresa; escalas 2025, 2026 y 2027 (AF-02) y tramo por días (AF-03)';

  -- ---------- 2. Ajustes propuestos ----------
  assert (select count(*) from erp.corporate_tax_proposals(e, 2026)) = 2, 'amortización y provisión';
  assert (select amount || ' ' || kind || ' ' || direction || ' ' || included || ' ' || article from erp.corporate_tax_proposals(e, 2026) where origin = 'depreciation')
         = '2600.00 temporary increase true LIS art. 12.1.a', 'exceso de amortización: 5.000 − 2.400';
  assert (select amount || ' ' || included from erp.corporate_tax_proposals(e, 2026) where origin = 'provision') = '12000.00 false',
         'la provisión del litigio se propone sin incluir';
  raise notice 'OK  · el ERP propone el exceso de amortización (2.600) y la provisión (sin incluir)';

  -- ---------- 3. Vista previa sin guardar ----------
  g := erp.corporate_tax_calc(e, 2026);
  assert g->>'status' = 'none' and (g->>'base_before_losses')::numeric = 184600, 'sin la multa todavía: 182.000 + 2.600 = 184.600: ' || g::text;

  -- ---------- 4. La declaración: borrador, multa manual y cálculo del supuesto ----------
  v_ret := erp.corporate_tax_prepare(e, 2026);
  assert erp.corporate_tax_prepare(e, 2026) = v_ret and (select count(*) from erp.corporate_tax_adjustments where return_id = v_ret) = 2, 'preparar dos veces no duplica';
  adj := erp.corporate_tax_manual(jsonb_build_object('return_id', v_ret, 'kind', 'permanent', 'direction', 'increase',
           'concept', 'Multa de tráfico', 'amount', 1000, 'article', 'LIS art. 15.c'));
  g := erp.corporate_tax_calc(e, 2026);
  assert g->>'regime' = 'micro' and (g->>'pre_tax_result')::numeric = 182000 and (g->>'permanent')::numeric = 1000
     and (g->>'temporary_increase')::numeric = 2600 and (g->>'base_before_losses')::numeric = 185600
     and (g->>'losses_compensated')::numeric = 0 and (g->>'taxable_base')::numeric = 185600, g::text;
  assert (g->>'quota')::numeric = 37976 and (g->>'withholdings')::numeric = 10000 and (g->>'differential')::numeric = 27976
     and g->>'outcome' = 'pay', 'cuota 37.976 − 10.000 = 27.976 a ingresar: ' || g::text;
  assert (g->>'deferred_rate')::numeric = 21 and (g->>'deferred_tax')::numeric = -546 and (g->>'tax_expense')::numeric = 37430
     and (g->>'net_result')::numeric = 144570, 'diferido −546, gasto 37.430, resultado 144.570: ' || g::text;
  assert jsonb_array_length(g->'warnings') = 0, g->>'warnings';
  raise notice 'OK  · supuesto 1: base 185.600, cuota 37.976, a ingresar 27.976, diferido −546, gasto 37.430';

  -- ---------- 5. Las temporarias cambian cuándo se paga, no el gasto ----------
  perform erp.corporate_tax_include((select id from erp.corporate_tax_adjustments where return_id = v_ret and origin = 'provision'), true);
  g := erp.corporate_tax_calc(e, 2026);
  assert (g->>'quota')::numeric = 40496 and (g->>'deferred_tax')::numeric = -3066 and (g->>'tax_expense')::numeric = 37430,
         'con la provisión como no deducible: cuota 40.496, diferido −3.066, el mismo gasto 37.430: ' || g::text;
  perform erp.corporate_tax_include((select id from erp.corporate_tax_adjustments where return_id = v_ret and origin = 'provision'), false);
  assert erp.corporate_tax_prepare(e, 2026) = v_ret
     and not (select included from erp.corporate_tax_adjustments where return_id = v_ret and origin = 'provision'), 'preparar otra vez respeta lo que quitaste';
  raise notice 'OK  · incluir la provisión sube la cuota (40.496) pero no el gasto (37.430): solo cambia cuándo se paga';

  -- ---------- 6. Régimen elegido y avisos ----------
  perform erp.corporate_tax_settings(v_ret, 'general', false);
  g := erp.corporate_tax_calc(e, 2026);
  assert (g->>'quota')::numeric = 46400 and (g->>'deferred_tax')::numeric = -650 and (g->>'tax_expense')::numeric = 45750, g::text;
  assert exists (select 1 from jsonb_array_elements(g->'warnings') w where w->>'code' = 'regime_mismatch' and w->>'suggested' = 'micro'),
         'avisa: por la cifra de negocios sería microempresa';
  perform erp.corporate_tax_settings(v_ret, 'micro', false);
  raise notice 'OK  · régimen general: cuota 46.400, gasto 45.750 = 183.000 × 25 %%, con aviso de que sería microempresa';

  -- ---------- 6 bis. Período impositivo más corto que el ejercicio (v0.60.2 · AF-03) ----------
  g := erp.corporate_tax_calc(e, 2026);
  assert g->>'period_start' = '2026-01-01' and (g->>'period_days')::int = 365 and g->'suggested_start' = 'null'::jsonb,
         'por defecto, el ejercicio entero y sin sugerencia: ' || g::text;
  update erp.companies set start_date = '2026-07-01' where id = e;
  assert erp.corporate_tax_calc(e, 2026)->>'suggested_start' = '2026-07-01', 'la fecha de inicio de la contabilidad se sugiere';
  assert (erp.corporate_tax_calc(e, 2026)->>'quota')::numeric = 37976, 'pero no se aplica sola';
  perform erp.corporate_tax_period(v_ret, '2026-07-01');
  g := erp.corporate_tax_calc(e, 2026);
  assert (g->>'period_days')::int = 184 and (g->>'quota')::numeric = 38471.89 and g->'suggested_start' = 'null'::jsonb,
         '184 días: 25.205,48 × 19 % + 160.394,52 × 21 % = 38.471,89: ' || g::text;
  assert ((g->'brackets')->0->>'upto')::numeric = 25205.48, 'el tramo que enseña la pantalla';
  assert public.falla(format($q$select erp.corporate_tax_period(%L, '2025-12-31')$q$, v_ret), 'within the fiscal year'), 'fuera del ejercicio: no';
  perform erp.corporate_tax_period(v_ret, '2026-01-01');
  assert (select period_start from erp.corporate_tax_returns where id = v_ret) is null
     and (erp.corporate_tax_calc(e, 2026)->>'quota')::numeric = 37976, 'el 1 de enero = el ejercicio entero, como antes';
  update erp.companies set start_date = null where id = e;
  raise notice 'OK  · período impositivo del 01-07 al 31-12: 184 días, tramo de 25.205,48 y cuota 38.471,89; por defecto, el año entero';

  -- ---------- 7. Ajustes manuales ----------
  perform erp.corporate_tax_manual(jsonb_build_object('id', adj, 'kind', 'permanent', 'direction', 'increase', 'concept', 'Multa de tráfico', 'amount', 1500));
  assert (erp.corporate_tax_calc(e, 2026)->>'permanent')::numeric = 1500;
  perform erp.corporate_tax_manual(jsonb_build_object('id', adj, 'delete', true));
  assert (erp.corporate_tax_calc(e, 2026)->>'permanent')::numeric = 0;
  perform erp.corporate_tax_manual(jsonb_build_object('return_id', v_ret, 'kind', 'permanent', 'direction', 'increase',
           'concept', 'Multa de tráfico', 'amount', 1000, 'article', 'LIS art. 15.c'));
  assert public.falla(format($q$select erp.corporate_tax_manual(jsonb_build_object('id', %L, 'delete', true))$q$,
         (select id from erp.corporate_tax_adjustments where return_id = v_ret and origin = 'depreciation')), 'Only manual'), 'los propuestos no se borran: se quitan';
  assert public.falla(format($q$select erp.corporate_tax_manual(jsonb_build_object('return_id', %L, 'kind', 'permanent', 'direction', 'increase', 'concept', 'x', 'amount', 0))$q$, v_ret), 'check'),
         'importe positivo';
  raise notice 'OK  · ajustes manuales: alta, cambio y baja; los propuestos solo se quitan';
end $$;

-- ---------- 8. Seguridad ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare e uuid := (select e from ctx);
begin
  assert (select count(*) from erp.corporate_tax_returns) = 0 and (select count(*) from erp.corporate_tax_adjustments) = 0, 'otro usuario no ve nada';
  assert public.falla(format('select erp.corporate_tax_calc(%L, 2026)', e), 'Not allowed');
  assert public.falla(format('select erp.corporate_tax_prepare(%L, 2026)', e), 'No permission');
  raise notice 'OK  · otro usuario no ve ni prepara el impuesto de una empresa ajena';
end $$;

\echo '✔ FASE 52 OK · Impuesto sobre Sociedades: cálculo, ajustes y régimen (supuesto de referencia 1)'
