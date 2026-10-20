-- =====================================================================
-- PRUEBAS FASE 53 · Impuesto sobre Sociedades (II): asientos, bases negativas y reversiones (migración 0058 · v0.41.0)
-- ---------------------------------------------------------------------
-- Cifras calculadas a mano desde la Ley 27/2014 y el PGC (NRV 13.ª), antes de ejecutar el ERP. Régimen general (25 %)
-- salvo el supuesto 1 (microempresa). Los tipos de 2026 están pendientes de validar en el BOE por Diosvely.
--
-- SUPUESTO 1 · el de la fase 52, contabilizado:
--   corriente: 6300 D 37.976 / 473 H 10.000 · 4752 H 27.976      diferido: 4740 D 546 / 6301 H 546
--   resultado después de impuestos = 182.000 − 37.976 + 546 = 144.570
-- SUPUESTO 2 · pérdidas y compensación (art. 26 LIS):
--   2026: pérdida 50.000 → base negativa 50.000. Con el crédito registrado: 4745 D 12.500 / 6301 H 12.500 (25 %);
--         resultado −50.000 + 12.500 = −37.500. Sin registrarlo: −50.000 y un aviso.
--   2027: beneficio 80.000; límite = máx(70 % × 80.000; 1.000.000 sin pasar de la base) = 80.000 → se compensan los
--         50.000; base 30.000; cuota 7.500 (6300 / 4752). Con crédito: 6301 D 12.500 / 4745 H 12.500 → gasto 20.000
--         (= 80.000 × 25 %), resultado 60.000. Sin crédito: gasto 7.500, resultado 72.500.
--   Límite del 70 %: pérdida de 2.000.000 en 2026 y beneficio de 2.000.000 en 2027 → se compensan 1.400.000
--         (70 %, que supera el millón); base 600.000; cuota 150.000; quedan 600.000 para 2028.
-- SUPUESTO 3 · pagos a cuenta mayores que la cuota: beneficio 20.000, cuota 5.000, 473 = 8.000
--   → 6300 D 5.000 · 4709 D 3.000 / 473 H 8.000 (a devolver)
-- SUPUESTO 4 · diferencias temporarias que revierten:
--   ordenador de 1.000 desde el 01/01/2026, vida útil 2 años (50 %), máximo fiscal 25 % (art. 12.1.a)
--     2026: contable 500, fiscal 250 → +250 · 2027: +250 · 2028: contable 0 (ya amortizado), fiscal 250 → −250
--   deterioro del 50 % de una factura de 1.210 vencida el 01/10/2026, al 31/12/2026: 605, no deducible (no han pasado
--   6 meses, art. 13.1.a) → +605 en 2026; al 31/12/2027 ya han pasado → −605 en 2027
--   2026: diferido 4740 D (250 + 605) × 25 % = 213,75 · 2027: 4740 H (605 − 250) × 25 % = 88,75 · 2028: 4740 H 62,50
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local');
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
create or replace function public.empresa(nombre text) returns uuid language plpgsql as $$
declare e uuid; c text;
begin
  insert into erp.companies (name, industry, tax_territory, created_by) values (nombre, 'services', 'mainland', auth.uid()) returning id into e;
  perform erp.create_fiscal_year(e, 2026); perform erp.create_fiscal_year(e, 2027); perform erp.create_fiscal_year(e, 2028);
  perform erp.setup_taxes(e);
  foreach c in array array['57200001:Banco', '70500001:Prestación de servicios', '62100001:Alquiler', '62900001:Otros servicios',
                           '67800001:Gastos excepcionales', '47300001:HP retenciones y pagos a cuenta', '21300001:Maquinaria',
                           '21700001:Equipos informáticos'] loop
    if not exists (select 1 from erp.gl_accounts where company_id = e and account_no = split_part(c, ':', 1)) then
      perform erp.create_posting_account(e, split_part(c, ':', 1), split_part(c, ':', 2));
    end if;
  end loop;
  return e;
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
create or replace function public.asiento(p uuid) returns text language sql as $$
  select string_agg(g.account_no || case when l.debit <> 0 then ' D ' || l.debit else ' H ' || l.credit end, ' | ' order by l.line_no)
  from erp.journal_lines l join erp.gl_accounts g on g.id = l.gl_account_id where l.entry_id = p;
$$;
create or replace function public.pyg(e uuid, y int) returns numeric language sql as $$
  select coalesce(sum(l.credit - l.debit), 0) from erp.journal_lines l join erp.journal_entries j on j.id = l.entry_id
  join erp.gl_accounts g on g.id = l.gl_account_id join erp.fiscal_years f on f.id = j.fiscal_year_id
  where j.company_id = e and f.year = y and j.status = 'posted' and left(g.account_no, 1) in ('6', '7');
$$;
create or replace function public.ret(e uuid, y int) returns erp.corporate_tax_returns language sql as $$
  select r.* from erp.corporate_tax_returns r join erp.fiscal_years f on f.id = r.fiscal_year_id where r.company_id = e and f.year = y;
$$;
grant execute on function public.falla(text, text), public.empresa(text), public.manual(uuid, date, jsonb), public.asiento(uuid),
  public.pyg(uuid, int), public.ret(uuid, int) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

-- ---------- Supuesto 1 ----------
do $$
declare e uuid := public.empresa('Supuesto 1 SL'); g jsonb; v_ret uuid;
begin
  perform public.manual(e, '2026-06-30', '[["57200001", 300000, 0], ["70500001", 0, 300000]]');
  perform public.manual(e, '2026-06-30', '[["62100001", 60000, 0], ["62900001", 40000, 0], ["57200001", 0, 100000]]');
  perform public.manual(e, '2026-09-10', '[["67800001", 1000, 0], ["57200001", 0, 1000]]');
  perform public.manual(e, '2026-10-20', '[["47300001", 10000, 0], ["57200001", 0, 10000]]');
  perform erp.create_provision(jsonb_build_object('company_id', e, 'kind', 'liabilities', 'term', 'long',
    'description', 'Demanda de un cliente', 'amount', 12000, 'provision_date', '2026-12-31', 'expense_account_no', '67800001'));
  perform erp.create_fixed_asset(jsonb_build_object('company_id', e, 'name', 'Máquina',
    'asset_account_no', '21300001', 'cost', 20000, 'start_date', '2026-01-01', 'useful_life_months', 48, 'class_code', 'MAQUINARIA'));
  perform erp.post_depreciation(e, '2026-12-31');
  v_ret := erp.corporate_tax_prepare(e, 2026);
  perform erp.corporate_tax_manual(jsonb_build_object('return_id', v_ret, 'kind', 'permanent', 'direction', 'increase',
           'concept', 'Multa de tráfico', 'amount', 1000, 'article', 'LIS art. 15.c'));
  g := erp.corporate_tax_post(e, 2026);
  assert g->>'status' = 'posted' and (g->>'differential')::numeric = 27976, g::text;
  assert public.asiento((public.ret(e, 2026)).current_entry_id) = '63000001 D 37976.00 | 47300001 H 10000.00 | 47520001 H 27976.00',
         public.asiento((public.ret(e, 2026)).current_entry_id);
  assert public.asiento((public.ret(e, 2026)).deferred_entry_id) = '47400001 D 546.00 | 63010001 H 546.00', public.asiento((public.ret(e, 2026)).deferred_entry_id);
  assert public.pyg(e, 2026) = 144570, 'resultado después de impuestos: ' || public.pyg(e, 2026);
  assert (erp.corporate_tax_calc(e, 2026)->>'status') = 'posted' and (erp.corporate_tax_calc(e, 2026)->>'tax_expense')::numeric = 37430, 'contabilizado: el cálculo guardado';
  raise notice 'OK  · supuesto 1 contabilizado: 6300 37.976 / 473 10.000 · 4752 27.976 y 4740 546 / 6301 546; resultado 144.570';

  -- módulo propio: no se anula desde el diario, no es manual, origen «corporate_tax»
  assert public.falla(format('select erp.reverse_entry(%L, %L, %L)', (public.ret(e, 2026)).current_entry_id, '2026-12-31', 'x'), 'corporate income tax'),
         'el asiento del impuesto no se anula desde el diario';
  assert (select distinct source from erp.v_general_journal where entry_id = (public.ret(e, 2026)).deferred_entry_id) = 'corporate_tax';
  assert public.falla(format('select erp.corporate_tax_prepare(%L, 2026)', e), 'already posted'), 'contabilizado: no se toca';
  -- deshacer y volver a contabilizar
  perform erp.corporate_tax_cancel(e, 2026);
  assert (public.ret(e, 2026)).status = 'draft' and public.pyg(e, 2026) = 182000, 'deshecho: vuelve el resultado antes de impuestos';
  perform erp.corporate_tax_post(e, 2026);
  assert public.pyg(e, 2026) = 144570;
  raise notice 'OK  · el asiento no se anula desde el diario; se deshace (contraasientos) y se vuelve a contabilizar';
end $$;

-- ---------- Supuesto 2 · pérdidas y compensación ----------
do $$
declare con uuid := public.empresa('Con crédito SL'); sin uuid := public.empresa('Sin crédito SL'); big uuid := public.empresa('Grande SL');
        g jsonb; v uuid;
begin
  foreach v in array array[con, sin] loop
    perform public.manual(v, '2026-06-30', '[["62900001", 50000, 0], ["57200001", 0, 50000]]');
    perform erp.corporate_tax_settings(erp.corporate_tax_prepare(v, 2026), 'general', v = con);
  end loop;
  g := erp.corporate_tax_post(con, 2026);
  assert (g->>'taxable_base')::numeric = -50000 and (g->>'loss_generated')::numeric = 50000 and (g->>'loss_credit')::numeric = 12500, g::text;
  assert (public.ret(con, 2026)).current_entry_id is null, 'sin cuota ni pagos a cuenta: no hay asiento corriente';
  assert public.asiento((public.ret(con, 2026)).deferred_entry_id) = '47450001 D 12500.00 | 63010001 H 12500.00', public.asiento((public.ret(con, 2026)).deferred_entry_id);
  assert public.pyg(con, 2026) = -37500;
  g := erp.corporate_tax_post(sin, 2026);
  assert (public.ret(sin, 2026)).deferred_entry_id is null and public.pyg(sin, 2026) = -50000
     and exists (select 1 from jsonb_array_elements(g->'warnings') w where w->>'code' = 'loss_credit_not_recognized'), g::text;
  raise notice 'OK  · 2026: pérdida de 50.000; con crédito 4745 12.500 (resultado −37.500), sin crédito −50.000 y un aviso';

  foreach v in array array[con, sin] loop
    perform public.manual(v, '2027-06-30', '[["57200001", 80000, 0], ["70500001", 0, 80000]]');
    perform erp.corporate_tax_settings(erp.corporate_tax_prepare(v, 2027), 'general', false);
  end loop;
  assert (select pending from erp.corporate_tax_loss_carryforwards(con, 2027)) = 50000;
  g := erp.corporate_tax_post(con, 2027);
  assert (g->>'losses_limit')::numeric = 80000 and (g->>'losses_compensated')::numeric = 50000 and (g->>'taxable_base')::numeric = 30000
     and (g->>'quota')::numeric = 7500 and (g->>'loss_credit_used')::numeric = 12500 and (g->>'tax_expense')::numeric = 20000, g::text;
  assert public.asiento((public.ret(con, 2027)).current_entry_id) = '63000001 D 7500.00 | 47520001 H 7500.00';
  assert public.asiento((public.ret(con, 2027)).deferred_entry_id) = '47450001 H 12500.00 | 63010001 D 12500.00', public.asiento((public.ret(con, 2027)).deferred_entry_id);
  assert public.pyg(con, 2027) = 60000 and not exists (select 1 from erp.corporate_tax_loss_carryforwards(con, 2028));
  g := erp.corporate_tax_post(sin, 2027);
  assert (g->>'tax_expense')::numeric = 7500 and public.pyg(sin, 2027) = 72500, g::text;
  assert public.falla(format('select erp.corporate_tax_cancel(%L, 2026)', con), 'later corporate tax'), 'no se deshace un año que usa el siguiente';
  raise notice 'OK  · 2027: se compensan los 50.000, cuota 7.500; con crédito el gasto es 20.000 (= 80.000 × 25 %%), sin él 7.500';

  perform public.manual(big, '2026-06-30', '[["62900001", 2000000, 0], ["57200001", 0, 2000000]]');
  perform erp.corporate_tax_settings(erp.corporate_tax_prepare(big, 2026), 'general', false);
  perform erp.corporate_tax_post(big, 2026);
  perform public.manual(big, '2027-06-30', '[["57200001", 2000000, 0], ["70500001", 0, 2000000]]');
  perform erp.corporate_tax_settings(erp.corporate_tax_prepare(big, 2027), 'general', false);
  g := erp.corporate_tax_post(big, 2027);
  assert (g->>'losses_limit')::numeric = 1400000 and (g->>'losses_compensated')::numeric = 1400000 and (g->>'quota')::numeric = 150000, g::text;
  assert (select pending from erp.corporate_tax_loss_carryforwards(big, 2028)) = 600000;
  raise notice 'OK  · límite del 70 %%: de 2.000.000 se compensan 1.400.000, cuota 150.000 y quedan 600.000';
end $$;

-- ---------- Supuesto 3 · a devolver ----------
do $$
declare e uuid := public.empresa('Devolución SL'); g jsonb;
begin
  perform public.manual(e, '2026-06-30', '[["57200001", 20000, 0], ["70500001", 0, 20000]]');
  perform public.manual(e, '2026-10-20', '[["47300001", 8000, 0], ["57200001", 0, 8000]]');
  perform erp.corporate_tax_settings(erp.corporate_tax_prepare(e, 2026), 'general', false);
  g := erp.corporate_tax_post(e, 2026);
  assert (g->>'differential')::numeric = -3000 and g->>'outcome' = 'refund', g::text;
  assert public.asiento((public.ret(e, 2026)).current_entry_id) = '63000001 D 5000.00 | 47300001 H 8000.00 | 47090001 D 3000.00',
         public.asiento((public.ret(e, 2026)).current_entry_id);
  raise notice 'OK  · supuesto 3: cuota 5.000, pagos a cuenta 8.000 → 4709 a devolver 3.000';
end $$;

-- ---------- Supuesto 4 · diferencias que revierten ----------
do $$
declare e uuid := public.empresa('Reversiones SL'); cli uuid; f uuid; g jsonb;
begin
  select partner_id into cli from erp.create_partner(e, 'customer', 'Cliente Lento SL', 'B11111119');
  select invoice_id into f from erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', 'sale', 'document_kind', 'invoice',
         'partner_id', cli, 'invoice_date', '2026-10-01', 'description', 'Servicio', 'lines',
         '[{"account_no":"70500001","amount":1000,"tax_code":"VAT21"}]'::jsonb));
  perform erp.impair_receivable(jsonb_build_object('invoice_id', f, 'impair_date', '2026-12-31', 'pct', 50));
  perform erp.create_fixed_asset(jsonb_build_object('company_id', e, 'name', 'Ordenador',
    'asset_account_no', '21700001', 'cost', 1000, 'start_date', '2026-01-01', 'useful_life_months', 24, 'class_code', 'INFORMATICA'));
  perform erp.post_depreciation(e, '2026-12-31');
  perform erp.corporate_tax_settings(erp.corporate_tax_prepare(e, 2026), 'general', false);
  assert (select string_agg(origin || ' ' || direction || ' ' || amount, ' · ' order by origin) from erp.corporate_tax_adjustments
          where return_id = (public.ret(e, 2026)).id) = 'depreciation increase 250.00 · receivable_impairment increase 605.00',
         (select string_agg(origin || ' ' || direction || ' ' || amount, ' · ' order by origin) from erp.corporate_tax_adjustments where return_id = (public.ret(e, 2026)).id);
  perform erp.corporate_tax_post(e, 2026);
  assert public.asiento((public.ret(e, 2026)).deferred_entry_id) = '47400001 D 213.75 | 63010001 H 213.75', public.asiento((public.ret(e, 2026)).deferred_entry_id);

  perform erp.post_depreciation(e, '2027-12-31');
  perform erp.corporate_tax_settings(erp.corporate_tax_prepare(e, 2027), 'general', false);
  assert (select string_agg(origin || ' ' || direction || ' ' || amount, ' · ' order by origin) from erp.corporate_tax_adjustments
          where return_id = (public.ret(e, 2027)).id) = 'depreciation increase 250.00 · receivable_impairment decrease 605.00',
         'el deterioro ya es deducible: revierte';
  perform erp.corporate_tax_post(e, 2027);
  assert public.asiento((public.ret(e, 2027)).deferred_entry_id) = '47400001 H 88.75 | 63010001 D 88.75', public.asiento((public.ret(e, 2027)).deferred_entry_id);

  perform erp.corporate_tax_settings(erp.corporate_tax_prepare(e, 2028), 'general', false);
  assert (select string_agg(origin || ' ' || direction || ' ' || amount, ' · ') from erp.corporate_tax_adjustments
          where return_id = (public.ret(e, 2028)).id) = 'depreciation decrease 250.00', 'ya amortizado contablemente: la fiscal sigue y revierte';
  raise notice 'OK  · supuesto 4: +250 y +605 en 2026 (4740 213,75), el deterioro revierte en 2027 (4740 H 88,75) y la amortización en 2028';
end $$;

reset role;
do $$
begin
  assert not exists (select 1 from erp.corporate_tax_returns r where erp.entry_is_manual(r.current_entry_id) or erp.entry_is_manual(r.deferred_entry_id)),
         'los asientos del impuesto no son manuales (no los marca el auditor como asientos a mano)';
  raise notice 'OK  · los asientos del impuesto no cuentan como asientos manuales';
end $$;

\echo '✔ FASE 53 OK · Impuesto sobre Sociedades: asientos, bases negativas y reversiones (supuestos 1 a 4)'
