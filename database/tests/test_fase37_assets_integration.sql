-- =====================================================================
-- PRUEBAS FASE 37 · Inmovilizado integrado (migración 0042)
--   comprobaciones (fichas frente a la contabilidad, amortización pendiente), aviso en el cierre, prorrata sin las
--   ventas de inmovilizado (art. 104.Tres.2.º LIVA) y conceptos del glosario
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);

create or replace function public.factura(e uuid, tipo text, tercero uuid, fecha date, lineas jsonb) returns uuid language sql as $$
  select invoice_id from erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', tipo, 'document_kind', 'invoice',
    'partner_id', tercero, 'external_document_no', case tipo when 'purchase' then 'P-' || substr(md5(random()::text), 1, 8) end,
    'invoice_date', fecha, 'description', 'Prueba', 'lines', lineas));
$$;
create or replace function public.chk(e uuid, c text, d date) returns text language sql as $$
  select r.status || ' · ' || r.items from erp.run_audit_checks(e, extract(year from d)::int, d) r where r.code = c;
$$;
grant execute on function public.factura(uuid, text, uuid, date, jsonb), public.chk(uuid, text, date) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare e uuid; prov uuid; cli uuid; f uuid; a uuid; r record; c jsonb; l uuid;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Integración Inmovilizado SL', 'services', 'mainland', auth.uid()) returning id into e;
  perform erp.create_fiscal_year(e, 2026);
  perform erp.setup_taxes(e);
  perform erp.create_posting_account(e, x.no, x.name) from (values
    ('21700001', 'Ordenadores'), ('57200001', 'Banco'), ('62900001', 'Otros servicios')) as x(no, name);
  select partner_id into prov from erp.create_partner(e, 'vendor', 'Suministros Técnicos SL', 'B12345674');
  select partner_id into cli  from erp.create_partner(e, 'customer', 'Cliente General SL', 'B11111119');

  -- ---------- 1. Conceptos del glosario ----------
  assert (select term from erp.concepts where key = 'fixedAsset') = 'Inmovilizado';
  assert (select string_agg(key, ',' order by key) from erp.concepts_for_account('28170001')) like '%netBookValue%', 'la 2817 → valor neto contable';
  raise notice 'OK  · conceptos «Inmovilizado» y «Valor neto contable» (la 2817 los encuentra)';

  -- ---------- 2. Amortización pendiente y fichas frente a la contabilidad ----------
  f := public.factura(e, 'purchase', prov, '2026-07-01', '[{"account_no":"21700001","amount":1200,"tax_code":"VAT21"}]');
  select asset_id into a from erp.create_fixed_asset(jsonb_build_object('company_id', e, 'name', 'Ordenador', 'asset_account_no', '21700001',
    'cost', 1200, 'start_date', '2026-07-01', 'useful_life_months', 48, 'invoice_id', f));
  assert public.chk(e, 'assets_ledger', '2026-12-31') = 'ok · 0', 'ficha = 21700001: ' || public.chk(e, 'assets_ledger', '2026-12-31');
  assert public.chk(e, 'assets_pending', '2026-12-31') = 'warning · 1', 'sin amortizar al 31/12: ' || public.chk(e, 'assets_pending', '2026-12-31');
  select * into r from erp.run_audit_checks(e, 2026, '2026-12-31') x where x.code = 'assets_pending';
  assert (r.details->0->>'amount')::numeric = 150 and r.screen = 'assets', '150 pendientes: ' || r.details::text;
  assert public.chk(e, 'assets_pending', '2026-12-15') = 'warning · 1', 'a mitad de mes mira el fin de mes anterior';
  select * into r from erp.run_audit_checks(e, 2026, '2026-12-15') x where x.code = 'assets_pending';
  assert (r.details->0->>'amount')::numeric = 125, 'hasta el 30/11: 5 meses × 25 = 125: ' || r.details::text;
  raise notice 'OK  · amortización pendiente: 150 al 31/12 (125 al 30/11 si se mira a mitad de diciembre)';

  -- ---------- 3. Aviso en el cierre ----------
  c := erp.year_closing_preview(e, 2026);
  assert c->'checks' @> jsonb_build_array(jsonb_build_object('code', 'assets_not_depreciated', 'severity', 'warning', 'detail', 'INM-0001')),
         'el cierre avisa: ' || (c->'checks')::text;
  perform erp.post_depreciation(e, '2026-12-31');
  c := erp.year_closing_preview(e, 2026);
  assert not (c->'checks' @> '[{"code":"assets_not_depreciated"}]'), 'amortizado, ya no avisa';
  assert public.chk(e, 'assets_pending', '2026-12-31') = 'ok · 0' and public.chk(e, 'assets_ledger', '2026-12-31') = 'ok · 0';
  raise notice 'OK  · el borrador del cierre avisa de los activos sin amortizar; amortizados, no';

  -- ---------- 4. Un asiento manual en la 21x (modo guiado) descuadra las fichas ----------
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and year = 2026), '2026-12-20', 'Ordenador comprado a mano') returning id into l;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit) values
    (l, e, 1, (select id from erp.gl_accounts where company_id = e and account_no = '21700001'), 700, 0),
    (l, e, 2, (select id from erp.gl_accounts where company_id = e and account_no = '57200001'), 0, 700);
  perform erp.post_entry(l);
  select * into r from erp.run_audit_checks(e, 2026, '2026-12-31') x where x.code = 'assets_ledger';
  assert r.status = 'warning' and r.items = 1 and r.details->0->>'account_no' = '21700001'
         and (r.details->0->>'book')::numeric = 1200 and (r.details->0->>'balance')::numeric = 1900, 'ficha 1.200 · cuenta 1.900: ' || r.details::text;
  raise notice 'OK  · un asiento manual a la 217 sin ficha: fichas 1.200 frente a la cuenta 1.900';
end $$;

-- ---------- 5. Prorrata: la venta de un bien de inversión no cuenta (art. 104.Tres.2.º LIVA) ----------
--  Mismo supuesto que la fase 35 (locales gravados 6.000, viviendas exentas 2.500 → 70,59 % → 71 %) más la venta de un
--  ordenador usado en la actividad por 10.000 + IVA. Si contara: (6.000 + 10.000) / 18.500 = 86,49 % → 87 %.
--  No cuenta en ningún término: la prorrata sigue en 71 %.
do $$
declare e uuid; obra uuid; local uuid; viv uuid; f uuid; a uuid; c jsonb;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Inmobiliaria con Venta SL', 'services', 'mainland', auth.uid()) returning id into e;
  perform erp.create_fiscal_year(e, 2026);
  perform erp.setup_taxes(e);
  perform erp.set_pro_rata(e, 'VAT', 2026, 80);
  perform erp.create_posting_account(e, x.no, x.name) from (values
    ('21700001', 'Ordenadores'), ('62200001', 'Reparaciones'), ('75200001', 'Arrendamientos')) as x(no, name);
  select partner_id into obra  from erp.create_partner(e, 'creditor', 'Reformas Pérez SL', 'B87654323');
  select partner_id into local from erp.create_partner(e, 'customer', 'Cliente General SL', 'B11111119');
  select partner_id into viv   from erp.create_partner(e, 'customer', 'Inquilino Vivienda', '11111111H');
  perform public.factura(e, 'purchase', obra, '2026-01-20', '[{"account_no":"62200001","amount":1000,"tax_code":"VAT21"}]');
  perform public.factura(e, 'sale', local, '2026-02-01', '[{"account_no":"75200001","amount":6000,"tax_code":"VAT21"}]');
  perform public.factura(e, 'sale', viv,   '2026-02-01', '[{"account_no":"75200001","amount":2500,"tax_code":"VAT_E20"}]');
  select asset_id into a from erp.create_fixed_asset(jsonb_build_object('company_id', e, 'name', 'Servidor', 'asset_account_no', '21700001',
    'cost', 12000, 'acquisition_date', '2025-01-01', 'start_date', '2025-01-01', 'useful_life_months', 48));
  f := public.factura(e, 'sale', local, '2026-06-30', '[{"account_no":"21700001","amount":10000,"tax_code":"VAT21"}]');
  perform erp.dispose_asset(jsonb_build_object('asset_id', a, 'disposal_date', '2026-06-30', 'invoice_id', f));
  c := erp.pro_rata_calc(e, 'VAT', 2026);
  assert (c->>'operations_with_right')::numeric = 6000 and (c->>'operations_total')::numeric = 8500,
         'la venta del servidor no cuenta: ' || (c->>'operations_with_right') || ' / ' || (c->>'operations_total');
  assert (c->>'definitive_pct')::numeric = 71, 'sigue en 71 %, no 87 %: ' || (c->>'definitive_pct');
  assert (select tax_amount from erp.v_invoice_register where invoice_id = f) = 2100, 'pero su IVA sí se repercute (2.100)';
  raise notice 'OK  · prorrata: la venta de un bien de inversión (10.000) no entra en ningún término; sigue en 71 %% (no 87 %%)';
end $$;

\echo '✔ FASE 37 OK · inmovilizado integrado'
